import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/mutations/field_patch.dart';

void main() {
  group('FieldPatch', () {
    test('absent preserves existing values', () {
      const patch = FieldPatch<String>.absent();

      expect(patch.isAbsent, isTrue);
      expect(patch.isPresent, isFalse);
      expect(patch.applyTo('current'), 'current');
    });

    test('value replaces existing values', () {
      const patch = FieldPatch<String>.value('updated');

      expect(patch.isPresent, isTrue);
      expect(patch.valueOrNull, 'updated');
      expect(patch.applyTo('current'), 'updated');
    });

    test('explicit null clears existing values', () {
      const patch = FieldPatch<String>.value(null);

      expect(patch.isPresent, isTrue);
      expect(patch.valueOrNull, isNull);
      expect(patch.applyTo('current'), isNull);
    });

    test('toDriftValue keeps absent separate from explicit null', () {
      const absent = FieldPatch<String>.absent();
      const cleared = FieldPatch<String>.value(null);

      final absentValue = absent.toDriftValue();
      final clearedValue = cleared.toDriftValue();

      expect(absentValue.present, isFalse);
      expect(clearedValue.present, isTrue);
      expect(clearedValue.value, isNull);
    });

    test('when dispatches by patch variant', () {
      const absent = FieldPatch<int>.absent();
      const present = FieldPatch<int>.value(42);

      final absentLabel = absent.when(
        absent: () => 'missing',
        value: (value) => 'value:$value',
      );
      final presentLabel = present.when(
        absent: () => 'missing',
        value: (value) => 'value:$value',
      );

      expect(absentLabel, 'missing');
      expect(presentLabel, 'value:42');
    });
  });
}
