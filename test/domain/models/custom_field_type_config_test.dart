import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/models/choice_option.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';

void main() {
  group('CustomFieldTypeConfig serialization', () {
    test('header icon descriptor round-trips as emoji', () {
      const c = TextConfig(headerIcon: CustomFieldHeaderIcon.emoji('🌙'));

      final json = CustomFieldTypeConfigCodec.toJson(c);
      expect(json['headerIcon'], {'type': 'emoji', 'emoji': '🌙'});

      final back = CustomFieldTypeConfigCodec.fromJson(json) as TextConfig;
      expect(back.headerIcon, const CustomFieldHeaderIcon.emoji('🌙'));
      expect(back.extra, isEmpty);
    });

    test('header icon descriptor round-trips as phosphor icon', () {
      const c = MemberConfig(
        headerIcon: CustomFieldHeaderIcon.phosphor('sparkle'),
      );

      final json = CustomFieldTypeConfigCodec.toJson(c);
      expect(json['headerIcon'], {'type': 'phosphor', 'name': 'sparkle'});

      final back = CustomFieldTypeConfigCodec.fromJson(json) as MemberConfig;
      expect(back.headerIcon, const CustomFieldHeaderIcon.phosphor('sparkle'));
      expect(back.extra, isEmpty);
    });

    test('header icon is a known key for every config variant', () {
      final variants = <CustomFieldTypeConfig>[
        const ChoiceConfig(headerIcon: CustomFieldHeaderIcon.emoji('🌙')),
        const GroupConfig(headerIcon: CustomFieldHeaderIcon.emoji('🌙')),
        const ScaleConfig(headerIcon: CustomFieldHeaderIcon.emoji('🌙')),
        const SliderConfig(
          mode: SliderMode.labeled,
          headerIcon: CustomFieldHeaderIcon.emoji('🌙'),
        ),
        const MemberConfig(headerIcon: CustomFieldHeaderIcon.emoji('🌙')),
        const TextConfig(headerIcon: CustomFieldHeaderIcon.emoji('🌙')),
        const ColorConfig(headerIcon: CustomFieldHeaderIcon.emoji('🌙')),
        const DateConfig(headerIcon: CustomFieldHeaderIcon.emoji('🌙')),
        const LongTextConfig(headerIcon: CustomFieldHeaderIcon.emoji('🌙')),
      ];

      for (final config in variants) {
        final json = CustomFieldTypeConfigCodec.toJson(config);
        final back = CustomFieldTypeConfigCodec.fromJson(json);
        expect(back.extra, isEmpty, reason: '$config duplicated headerIcon');
        expect(
          effectiveHeaderIcon(back),
          const CustomFieldHeaderIcon.emoji('🌙'),
        );
      }
    });

    test('ChoiceConfig round-trips', () {
      const c = ChoiceConfig(
        options: [
          ChoiceOption(
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

    test('ChoiceConfig round-trips with displayLayout override', () {
      const c = ChoiceConfig(displayLayout: DisplayLayout.stacked);

      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as ChoiceConfig;

      expect(json['displayLayout'], 'stacked');
      expect(back, c);
      expect(back.displayLayout, DisplayLayout.stacked);
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

    test('MemberConfig round-trips', () {
      const c = MemberConfig(
        displayLayout: DisplayLayout.stacked,
        hideTitleOnProfile: true,
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
      expect(config.extra['displayMode'], {
        'style': 'compact',
        'showNumbers': false,
      });

      final reemitted = CustomFieldTypeConfigCodec.toJson(config);
      expect(reemitted['allowHalfSteps'], true);
      expect(reemitted['displayMode'], {
        'style': 'compact',
        'showNumbers': false,
      });
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

    test('unknown keys for MemberConfig survive round-trip', () {
      final json = {
        'runtimeType': 'member',
        'hideTitleOnProfile': false,
        'selectionMode': 'multiple',
      };
      final config = CustomFieldTypeConfigCodec.fromJson(json) as MemberConfig;
      expect(config.extra['selectionMode'], 'multiple');

      final reemitted = CustomFieldTypeConfigCodec.toJson(config);
      expect(reemitted['selectionMode'], 'multiple');
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
      expect(
        config.extra,
        isEmpty,
        reason: 'Known keys must not appear in extra',
      );
    });

    test('runtimeType key is never placed in extra', () {
      final json = {'runtimeType': 'group', 'icon': null};
      final config = CustomFieldTypeConfigCodec.fromJson(json) as GroupConfig;
      expect(config.extra.containsKey('runtimeType'), isFalse);
    });

    test('codec re-encoding is order-independent: two inputs differing only in '
        'extras-key order produce byte-identical output', () {
      // Parse JSON strings so the test controls on-the-wire key order.
      const extrasFirst =
          '{"zeta":"z","alpha":"a","runtimeType":"slider",'
          '"mode":"labeled","leftLabel":"A","rightLabel":"B",'
          '"snapToPositions":true,"showTicks":false}';
      const extrasLast =
          '{"runtimeType":"slider","mode":"labeled",'
          '"leftLabel":"A","rightLabel":"B","snapToPositions":true,'
          '"showTicks":false,"alpha":"a","zeta":"z"}';

      final outA = jsonEncode(
        CustomFieldTypeConfigCodec.toJson(
          CustomFieldTypeConfigCodec.fromJson(
            jsonDecode(extrasFirst) as Map<String, dynamic>,
          ),
        ),
      );
      final outB = jsonEncode(
        CustomFieldTypeConfigCodec.toJson(
          CustomFieldTypeConfigCodec.fromJson(
            jsonDecode(extrasLast) as Map<String, dynamic>,
          ),
        ),
      );

      expect(
        outA,
        outB,
        reason:
            'Re-encoding must be order-independent so any v29-peer write '
            'round-trips byte-identically — no phantom sync emits',
      );

      // And idempotent across N passes.
      final outA2 = jsonEncode(
        CustomFieldTypeConfigCodec.toJson(
          CustomFieldTypeConfigCodec.fromJson(
            jsonDecode(outA) as Map<String, dynamic>,
          ),
        ),
      );
      expect(outA2, outA, reason: 'Idempotent across passes');
    });

    test('codec re-encoding is order-independent for ChoiceConfig with extras '
        'in both top-level and nested ChoiceOption', () {
      const a =
          '{"zeta_top":1,"runtimeType":"choice",'
          '"options":[{"zeta_opt":"z","id":"1","label":"foo","alpha_opt":"a"}],'
          '"alpha_top":2,'
          '"allowsMultiple":false,"allowsOther":false}';
      const b =
          '{"runtimeType":"choice","alpha_top":2,'
          '"options":[{"alpha_opt":"a","id":"1","label":"foo","zeta_opt":"z"}],'
          '"allowsMultiple":false,"allowsOther":false,"zeta_top":1}';

      final outA = jsonEncode(
        CustomFieldTypeConfigCodec.toJson(
          CustomFieldTypeConfigCodec.fromJson(
            jsonDecode(a) as Map<String, dynamic>,
          ),
        ),
      );
      final outB = jsonEncode(
        CustomFieldTypeConfigCodec.toJson(
          CustomFieldTypeConfigCodec.fromJson(
            jsonDecode(b) as Map<String, dynamic>,
          ),
        ),
      );
      expect(
        outA,
        outB,
        reason:
            'Order-independent for both top-level extras and nested '
            'ChoiceOption extras',
      );
    });

    test('unknown keys inside ChoiceOption survive round-trip', () {
      // Forward-compat: a v29 peer adds a key to ChoiceOption (e.g. iconKey).
      // A v28 device must preserve that key byte-for-byte on read→write.
      final json = {
        'runtimeType': 'choice',
        'options': <dynamic>[
          {'id': '1', 'label': 'foo', 'iconKey': 'bar', 'futureField': 42},
        ],
        'allowsMultiple': false,
        'allowsOther': false,
      };

      final config = CustomFieldTypeConfigCodec.fromJson(json) as ChoiceConfig;
      expect(config.options, hasLength(1));
      expect(config.options.first.id, '1');
      expect(config.options.first.label, 'foo');

      final reemitted = CustomFieldTypeConfigCodec.toJson(config);
      final options = reemitted['options'] as List<dynamic>;
      expect(options, hasLength(1));
      final opt = options.first as Map<String, dynamic>;
      expect(
        opt['iconKey'],
        'bar',
        reason: 'Unknown ChoiceOption keys must survive read→write',
      );
      expect(
        opt['futureField'],
        42,
        reason: 'Unknown ChoiceOption keys must survive read→write',
      );
    });

    test('ChoiceConfig with multiple ChoiceOptions round-trips', () {
      const c = ChoiceConfig(
        options: [
          ChoiceOption(id: 'a', label: 'Alpha', sortOrder: 0),
          ChoiceOption(
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

    // -------------------------------------------------------------------------
    // gradientColorsHex tests (new multi-color gradient support)
    // -------------------------------------------------------------------------

    test(
      'SliderConfig with gradientColorsHex round-trips (5 colors) and extra is empty',
      () {
        const c = SliderConfig(
          mode: SliderMode.labeled,
          gradientColorsHex: [
            '#112233',
            '#445566',
            '#778899',
            '#aabbcc',
            '#ddeeff',
          ],
        );
        final json = CustomFieldTypeConfigCodec.toJson(c);
        final back = CustomFieldTypeConfigCodec.fromJson(json) as SliderConfig;
        expect(back.gradientColorsHex, [
          '#112233',
          '#445566',
          '#778899',
          '#aabbcc',
          '#ddeeff',
        ]);
        expect(
          back.extra,
          isEmpty,
          reason: 'gradientColorsHex must be a known key — not land in extra',
        );
      },
    );

    test('SliderConfig old data (no gradientColorsHex) decodes with null', () {
      final json = {
        'runtimeType': 'slider',
        'mode': 'labeled',
        'leftColorHex': '#ff0000',
        'rightColorHex': '#0000ff',
        'centerColorHex': '#00ff00',
      };
      final config = CustomFieldTypeConfigCodec.fromJson(json) as SliderConfig;
      expect(config.gradientColorsHex, isNull);
      // Re-encoding: nullable list fields are emitted as null (same as stepLabels
      // on ScaleConfig). The key is present but null — it must NOT land in extra.
      final reemitted = CustomFieldTypeConfigCodec.toJson(config);
      expect(
        reemitted['gradientColorsHex'],
        isNull,
        reason:
            'null gradientColorsHex should be emitted as null, not as extra',
      );
      expect(
        config.extra,
        isEmpty,
        reason:
            'gradientColorsHex must be recognized as a known key even when absent from input',
      );
    });

    test(
      'SliderConfig with gradientColorsHex: decode→encode→decode is a fixed point',
      () {
        final original = {
          'runtimeType': 'slider',
          'mode': 'labeled',
          'gradientColorsHex': ['#112233', '#445566', '#778899'],
          'leftLabel': 'Start',
          'rightLabel': 'End',
          'snapToPositions': false,
          'showTicks': false,
        };
        final pass1 = CustomFieldTypeConfigCodec.toJson(
          CustomFieldTypeConfigCodec.fromJson(original),
        );
        final pass2 = CustomFieldTypeConfigCodec.toJson(
          CustomFieldTypeConfigCodec.fromJson(pass1),
        );
        expect(pass2, pass1, reason: 'Re-encoding must be a fixed point');
      },
    );
  });

  // ---------------------------------------------------------------------------
  // hideTitleOnProfile field on existing and new variants
  // ---------------------------------------------------------------------------
  group('hideTitleOnProfile — new variants and extended fields', () {
    test('TextConfig round-trips with hideTitleOnProfile: true', () {
      const c = TextConfig(hideTitleOnProfile: true);
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as TextConfig;
      expect(back, c);
      expect(back.hideTitleOnProfile, isTrue);
    });

    test('TextConfig round-trips with hideTitleOnProfile: false (default)', () {
      const c = TextConfig();
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as TextConfig;
      expect(back, c);
      expect(back.hideTitleOnProfile, isFalse);
    });

    test('ColorConfig round-trips with hideTitleOnProfile: true', () {
      const c = ColorConfig(hideTitleOnProfile: true);
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as ColorConfig;
      expect(back, c);
      expect(back.hideTitleOnProfile, isTrue);
    });

    test('ColorConfig round-trips with hideTitleOnProfile: false', () {
      const c = ColorConfig();
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as ColorConfig;
      expect(back, c);
      expect(back.hideTitleOnProfile, isFalse);
    });

    test('DateConfig round-trips with hideTitleOnProfile: true', () {
      const c = DateConfig(hideTitleOnProfile: true);
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as DateConfig;
      expect(back, c);
      expect(back.hideTitleOnProfile, isTrue);
    });

    test('DateConfig round-trips with hideTitleOnProfile: false', () {
      const c = DateConfig();
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as DateConfig;
      expect(back, c);
      expect(back.hideTitleOnProfile, isFalse);
    });

    test('LongTextConfig round-trips with hideTitleOnProfile: true', () {
      const c = LongTextConfig(hideTitleOnProfile: true);
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as LongTextConfig;
      expect(back, c);
      expect(back.hideTitleOnProfile, isTrue);
    });

    test('LongTextConfig round-trips with hideTitleOnProfile: false', () {
      const c = LongTextConfig();
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as LongTextConfig;
      expect(back, c);
      expect(back.hideTitleOnProfile, isFalse);
    });

    test('ChoiceConfig round-trips with hideTitleOnProfile: true', () {
      const c = ChoiceConfig(
        hideTitleOnProfile: true,
        options: [ChoiceOption(id: 'o1', label: 'Opt', sortOrder: 0)],
      );
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as ChoiceConfig;
      expect(back, c);
      expect(back.hideTitleOnProfile, isTrue);
    });

    test('ScaleConfig round-trips with hideTitleOnProfile: true', () {
      const c = ScaleConfig(hideTitleOnProfile: true);
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as ScaleConfig;
      expect(back, c);
      expect(back.hideTitleOnProfile, isTrue);
    });

    test('SliderConfig round-trips with hideTitleOnProfile: true', () {
      const c = SliderConfig(
        mode: SliderMode.labeled,
        hideTitleOnProfile: true,
      );
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as SliderConfig;
      expect(back, c);
      expect(back.hideTitleOnProfile, isTrue);
    });

    test('MemberConfig round-trips with hideTitleOnProfile: true', () {
      const c = MemberConfig(hideTitleOnProfile: true);
      final json = CustomFieldTypeConfigCodec.toJson(c);
      final back = CustomFieldTypeConfigCodec.fromJson(json) as MemberConfig;
      expect(back, c);
      expect(back.hideTitleOnProfile, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // effectiveHideTitleOnProfile helper
  // ---------------------------------------------------------------------------
  group('effectiveHideTitleOnProfile', () {
    test('null config returns false', () {
      expect(effectiveHideTitleOnProfile(null), isFalse);
    });

    test('GroupConfig with hideTitleOnProfile: true returns true', () {
      expect(
        effectiveHideTitleOnProfile(
          const GroupConfig(hideTitleOnProfile: true),
        ),
        isTrue,
      );
    });

    test('GroupConfig with hideTitleOnProfile: false returns false', () {
      expect(effectiveHideTitleOnProfile(const GroupConfig()), isFalse);
    });

    test('TextConfig with hideTitleOnProfile: true returns true', () {
      expect(
        effectiveHideTitleOnProfile(const TextConfig(hideTitleOnProfile: true)),
        isTrue,
      );
    });

    test('ColorConfig with hideTitleOnProfile: true returns true', () {
      expect(
        effectiveHideTitleOnProfile(
          const ColorConfig(hideTitleOnProfile: true),
        ),
        isTrue,
      );
    });

    test('DateConfig with hideTitleOnProfile: true returns true', () {
      expect(
        effectiveHideTitleOnProfile(const DateConfig(hideTitleOnProfile: true)),
        isTrue,
      );
    });

    test('LongTextConfig with hideTitleOnProfile: true returns true', () {
      expect(
        effectiveHideTitleOnProfile(
          const LongTextConfig(hideTitleOnProfile: true),
        ),
        isTrue,
      );
    });

    test('ChoiceConfig with hideTitleOnProfile: false returns false', () {
      expect(effectiveHideTitleOnProfile(const ChoiceConfig()), isFalse);
    });

    test('ScaleConfig with hideTitleOnProfile: false returns false', () {
      expect(effectiveHideTitleOnProfile(const ScaleConfig()), isFalse);
    });

    test('SliderConfig with hideTitleOnProfile: true returns true', () {
      expect(
        effectiveHideTitleOnProfile(
          const SliderConfig(
            mode: SliderMode.labeled,
            hideTitleOnProfile: true,
          ),
        ),
        isTrue,
      );
    });

    test('MemberConfig with hideTitleOnProfile: true returns true', () {
      expect(
        effectiveHideTitleOnProfile(
          const MemberConfig(hideTitleOnProfile: true),
        ),
        isTrue,
      );
    });

    test('MemberConfig displayLayout overrides the compact default', () {
      expect(
        effectiveDisplayLayout(
          fieldTypeId: 'member',
          typeConfig: const MemberConfig(),
        ),
        DisplayLayout.compact,
      );
      expect(
        effectiveDisplayLayout(
          fieldTypeId: 'member',
          typeConfig: const MemberConfig(displayLayout: DisplayLayout.stacked),
        ),
        DisplayLayout.stacked,
      );
    });

    test('ChoiceConfig displayLayout overrides the compact default', () {
      expect(
        effectiveDisplayLayout(
          fieldTypeId: 'choice',
          typeConfig: const ChoiceConfig(),
        ),
        DisplayLayout.compact,
      );
      expect(
        effectiveDisplayLayout(
          fieldTypeId: 'choice',
          typeConfig: const ChoiceConfig(displayLayout: DisplayLayout.stacked),
        ),
        DisplayLayout.stacked,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Combinatorial: known fields must NOT appear in extra after round-trip
  // (codec-correctness footgun guard — catches any variant missing a key in
  // _knownKeysFor that would silently duplicate the field into both the typed
  // field and `extra`).
  // ---------------------------------------------------------------------------
  group('known fields are NOT duplicated into extra — combinatorial', () {
    Map<String, dynamic> makeJson(
      String runtimeType,
      Map<String, dynamic> fields,
    ) => {'runtimeType': runtimeType, ...fields};

    void assertNoExtraLeakage(String label, Map<String, dynamic> json) {
      final config = CustomFieldTypeConfigCodec.fromJson(json);
      final extra = switch (config) {
        final ChoiceConfig c => c.extra,
        final GroupConfig c => c.extra,
        final ScaleConfig c => c.extra,
        final SliderConfig c => c.extra,
        final MemberConfig c => c.extra,
        final TextConfig c => c.extra,
        final ColorConfig c => c.extra,
        final DateConfig c => c.extra,
        final LongTextConfig c => c.extra,
      };
      expect(
        extra,
        isEmpty,
        reason: 'Known key in $label must not appear in extra',
      );
    }

    // ChoiceConfig known keys
    test('ChoiceConfig — each known key individually stays out of extra', () {
      for (final key in [
        'options',
        'allowsMultiple',
        'allowsOther',
        'displayLayout',
        'hideTitleOnProfile',
      ]) {
        final json = makeJson('choice', {
          'options': <dynamic>[],
          'allowsMultiple': false,
          'allowsOther': false,
          'displayLayout': null,
          'hideTitleOnProfile': false,
          // Ensure the specific key is present
        });
        json[key] = json[key]; // already set; just confirm it's there
        assertNoExtraLeakage('ChoiceConfig/$key', json);
      }
    });

    // GroupConfig known keys
    test('GroupConfig — each known key individually stays out of extra', () {
      for (final key in ['icon', 'hideTitleOnProfile']) {
        final json = makeJson('group', {
          'icon': null,
          'hideTitleOnProfile': false,
        });
        json[key] = json[key];
        assertNoExtraLeakage('GroupConfig/$key', json);
      }
    });

    // ScaleConfig known keys
    test('ScaleConfig — each known key individually stays out of extra', () {
      for (final key in [
        'emoji',
        'steps',
        'stepLabels',
        'displayLayout',
        'hideTitleOnProfile',
      ]) {
        final json = makeJson('scale', {
          'emoji': '⭐',
          'steps': 5,
          'stepLabels': null,
          'displayLayout': null,
          'hideTitleOnProfile': false,
        });
        json[key] = json[key];
        assertNoExtraLeakage('ScaleConfig/$key', json);
      }
    });

    // SliderConfig known keys
    test('SliderConfig — each known key individually stays out of extra', () {
      for (final key in [
        'mode',
        'leftLabel',
        'rightLabel',
        'centerLabel',
        'gradientPresetId',
        'leftColorHex',
        'rightColorHex',
        'centerColorHex',
        'gradientColorsHex',
        'snapToPositions',
        'min',
        'max',
        'step',
        'unit',
        'showTicks',
        'hideTitleOnProfile',
      ]) {
        final json = makeJson('slider', {
          'mode': 'labeled',
          'leftLabel': null,
          'rightLabel': null,
          'centerLabel': null,
          'gradientPresetId': null,
          'leftColorHex': null,
          'rightColorHex': null,
          'centerColorHex': null,
          'gradientColorsHex': null,
          'snapToPositions': false,
          'min': null,
          'max': null,
          'step': null,
          'unit': null,
          'showTicks': false,
          'hideTitleOnProfile': false,
        });
        json[key] = json[key];
        assertNoExtraLeakage('SliderConfig/$key', json);
      }
    });

    test('MemberConfig — each known key individually stays out of extra', () {
      for (final key in ['displayLayout', 'hideTitleOnProfile']) {
        final json = makeJson('member', {
          'displayLayout': null,
          'hideTitleOnProfile': false,
        });
        json[key] = json[key];
        assertNoExtraLeakage('MemberConfig/$key', json);
      }
    });

    // TextConfig known keys
    test('TextConfig — each known key individually stays out of extra', () {
      for (final key in ['hideTitleOnProfile']) {
        final json = makeJson('text', {'hideTitleOnProfile': false});
        json[key] = json[key];
        assertNoExtraLeakage('TextConfig/$key', json);
      }
    });

    // ColorConfig known keys
    test('ColorConfig — each known key individually stays out of extra', () {
      for (final key in ['hideTitleOnProfile']) {
        final json = makeJson('color', {'hideTitleOnProfile': false});
        json[key] = json[key];
        assertNoExtraLeakage('ColorConfig/$key', json);
      }
    });

    // DateConfig known keys
    test('DateConfig — each known key individually stays out of extra', () {
      for (final key in ['hideTitleOnProfile']) {
        final json = makeJson('date', {'hideTitleOnProfile': false});
        json[key] = json[key];
        assertNoExtraLeakage('DateConfig/$key', json);
      }
    });

    // LongTextConfig known keys
    test('LongTextConfig — each known key individually stays out of extra', () {
      for (final key in ['hideTitleOnProfile']) {
        final json = makeJson('longText', {'hideTitleOnProfile': false});
        json[key] = json[key];
        assertNoExtraLeakage('LongTextConfig/$key', json);
      }
    });
  });
}
