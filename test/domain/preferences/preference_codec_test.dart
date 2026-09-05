import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/preferences/fronting_terms.dart';
import 'package:prism_plurality/domain/preferences/preference_codec.dart';
import 'package:prism_plurality/domain/preferences/system_terms.dart';

import '../../helpers/fronting_term_fixtures.dart';

void main() {
  test('primitive codecs round-trip valid values', () {
    expect(const BoolPreferenceCodec().decode(true), isTrue);
    expect(const IntPreferenceCodec(min: 1, max: 3).isValid(2), isTrue);
    expect(const DoublePreferenceCodec().decode(2), 2.0);
    expect(
      const StringPreferenceCodec(
        allowedValues: {'compact', 'comfortable'},
      ).isValid('compact'),
      isTrue,
    );
  });

  test('codecs reject invalid values', () {
    expect(const IntPreferenceCodec(min: 1).isValid(0), isFalse);
    expect(const DoublePreferenceCodec().isValid(double.nan), isFalse);
    expect(
      const StringPreferenceCodec(allowedValues: {'a'}).isValid('b'),
      isFalse,
    );
    expect(
      () => const BoolPreferenceCodec().decode('true'),
      throwsA(isA<PreferenceDecodeException>()),
    );
  });

  test('system terms codec validates complete bounded pairs', () {
    const codec = SystemTermsPreferenceCodec();
    const terms = SystemTerms.custom(
      singular: 'collective',
      plural: 'collectives',
    );

    expect(codec.isValid(terms), isTrue);
    expect(codec.decode(codec.encode(terms)), terms);
    expect(
      codec.encode(const SystemTerms.preset(SystemTermPreset.collective)),
      {'preset': 'collective'},
    );
    expect(
      codec.decode(
        codec.encode(const SystemTerms.preset(SystemTermPreset.collective)),
      ),
      const SystemTerms.preset(SystemTermPreset.collective),
    );
    expect(
      codec.isValid(const SystemTerms.preset(SystemTermPreset.collective)),
      isTrue,
    );
    expect(codec.isValid(const SystemTerms(singular: 'collective')), isFalse);
    expect(codec.isValid(const SystemTerms(plural: 'collectives')), isFalse);
    expect(
      codec.isValid(
        SystemTerms.custom(
          singular: 'x' * (systemTermMaxLength + 1),
          plural: 'collectives',
        ),
      ),
      isFalse,
    );
  });

  test('system terms codec decodes malformed values to unset', () {
    const codec = SystemTermsPreferenceCodec();

    expect(codec.decode(null), SystemTerms.unset);
    expect(codec.decode('not a map'), SystemTerms.unset);
    expect(codec.decode({'preset': 'bogus'}), SystemTerms.unset);
    expect(codec.decode({'singular': 'collective'}), SystemTerms.unset);
    expect(codec.decode({'plural': 'collectives'}), SystemTerms.unset);
    expect(
      codec.decode({
        'singular': 'x' * (systemTermMaxLength + 1),
        'plural': 'collectives',
      }),
      SystemTerms.unset,
    );
  });

  test('fronting terms codec validates presets and custom bundles', () {
    const codec = FrontingTermsPreferenceCodec();
    final custom = FrontingTerms.custom(testFrontingTermBundle);

    expect(codec.isValid(custom), isTrue);
    expect(codec.decode(codec.encode(custom)), custom);
    expect(codec.encode(const FrontingTerms.preset(FrontingTermPreset.out)), {
      'preset': 'out',
    });
    expect(
      codec.decode(
        codec.encode(const FrontingTerms.preset(FrontingTermPreset.online)),
      ),
      const FrontingTerms.preset(FrontingTermPreset.online),
    );
    expect(
      codec.isValid(const FrontingTerms.preset(FrontingTermPreset.present)),
      isTrue,
    );
    expect(codec.isValid(FrontingTerms.unset), isFalse);
  });

  test('fronting terms codec preserves a missing legacy singular header', () {
    const codec = FrontingTermsPreferenceCodec();
    final legacyBundle = Map<String, Object?>.from(
      testFrontingTermBundle.toJson(),
    )..remove('longRunningHeaderSingularLabel');

    final decoded = codec.decode({'custom': legacyBundle});

    expect(decoded.custom, isNotNull);
    expect(
      decoded.custom!.longRunningHeaderSingularLabel,
      decoded.custom!.longRunningHeaderLabel,
    );
    expect((codec.encode(decoded)! as Map)['custom'], legacyBundle);
    expect(codec.decode(codec.encode(decoded)), decoded);
    expect(
      codec.decode({
        'custom': {...legacyBundle, 'longRunningHeaderSingularLabel': null},
      }),
      decoded,
    );
  });

  test(
    'fronting terms codec retains an inactive custom draft with a preset',
    () {
      const codec = FrontingTermsPreferenceCodec();
      final terms = FrontingTerms.preset(
        FrontingTermPreset.out,
        custom: testFrontingTermBundle,
      );

      expect(codec.decode(codec.encode(terms)), terms);
      expect(codec.encode(terms), {
        'preset': 'out',
        'custom': testFrontingTermBundle.toJson(),
      });
    },
  );

  test(
    'fronting terms codec round-trips optional simple authoring metadata',
    () {
      const codec = FrontingTermsPreferenceCodec();
      const authoring = SimpleFrontingTermAuthoring(
        locale: 'en',
        seedPreset: FrontingTermPreset.fronting,
        featureLabel: 'Orbit',
        activeSectionLabel: 'In Orbit',
        statePhrase: 'in orbit',
        activeSingularLabel: 'Orbiter',
        activePluralLabel: 'Orbiters',
        sessionSingular: 'Orbit session',
        sessionPlural: 'Orbit sessions',
      );
      final terms = FrontingTerms.custom(
        testFrontingTermBundle,
        authoring: authoring,
      );

      expect(codec.decode(codec.encode(terms)), terms);
      expect((codec.encode(terms)! as Map)['authoring'], authoring.toJson());
    },
  );

  test('malformed simple metadata does not invalidate a custom bundle', () {
    const codec = FrontingTermsPreferenceCodec();
    final decoded = codec.decode({
      'custom': testFrontingTermBundle.toJson(),
      'authoring': {'kind': 'simple', 'version': 999, 'locale': 'en'},
    });

    expect(decoded.custom, testFrontingTermBundle);
    expect(decoded.authoring, isNull);
  });

  test('fronting terms codec decodes malformed values to unset', () {
    const codec = FrontingTermsPreferenceCodec();
    final encoded = testFrontingTermBundle.toJson();

    expect(codec.decode(null), FrontingTerms.unset);
    expect(codec.decode('not a map'), FrontingTerms.unset);
    expect(codec.decode({'preset': 'bogus'}), FrontingTerms.unset);
    expect(
      codec.decode({
        'custom': {'featureLabel': 'Only one'},
      }),
      {FrontingTerms.unset}.single,
    );
    expect(
      codec.decode({
        'custom': {
          ...encoded,
          'featureLabel': 'x' * (frontingTermMaxLength + 1),
        },
      }),
      FrontingTerms.unset,
    );
  });
}
