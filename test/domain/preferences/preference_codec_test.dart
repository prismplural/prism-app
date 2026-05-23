import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/preferences/preference_codec.dart';

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
}
