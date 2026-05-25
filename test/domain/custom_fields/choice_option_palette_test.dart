import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/domain/custom_fields/choice_option_palette.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';

void main() {
  group('Choice field palette helpers', () {
    test('palette has exactly 10 swatches', () {
      expect(kChoiceOptionPalette.length, equals(10));
    });

    test('nextChoicePaletteColor cycles through palette', () {
      for (var i = 0; i < 25; i++) {
        final color = nextChoicePaletteColor(i);
        expect(kChoiceOptionPalette.contains(color), isTrue);
        expect(
          color,
          equals(kChoiceOptionPalette[i % kChoiceOptionPalette.length]),
        );
      }
    });

    test('cycleChoicePaletteColor advances by one', () {
      final first = kChoiceOptionPalette[0];
      final second = kChoiceOptionPalette[1];
      expect(cycleChoicePaletteColor(first), equals(second));
    });

    test('cycleChoicePaletteColor wraps at end', () {
      final last = kChoiceOptionPalette.last;
      final first = kChoiceOptionPalette[0];
      expect(cycleChoicePaletteColor(last), equals(first));
    });

    test('cycleChoicePaletteColor with null starts at index 0', () {
      expect(cycleChoicePaletteColor(null), equals(kChoiceOptionPalette[0]));
    });

    test('choicePaletteIndex returns null for unknown hex', () {
      expect(choicePaletteIndex('#FFFFFF'), isNull);
    });

    test('choicePaletteIndex returns null for null input', () {
      expect(choicePaletteIndex(null), isNull);
    });

    test('choicePaletteIndex finds all known palette colors', () {
      for (var i = 0; i < kChoiceOptionPalette.length; i++) {
        expect(
          choicePaletteIndex(kChoiceOptionPalette[i]),
          equals(i),
          reason: 'palette[$i] = ${kChoiceOptionPalette[i]}',
        );
      }
    });

    test('choicePaletteIndex is case-insensitive', () {
      // First swatch is '#E57373' — match both upper and lower.
      expect(choicePaletteIndex('#e57373'), equals(0));
      expect(choicePaletteIndex('#E57373'), equals(0));
    });

    test('choicePaletteIndex trims surrounding whitespace', () {
      expect(choicePaletteIndex('  #e57373  '), equals(0));
    });

    test('cycleChoicePaletteColor full round-trip', () {
      // Walk from each palette color and verify each step.
      for (var i = 0; i < kChoiceOptionPalette.length; i++) {
        final current = kChoiceOptionPalette[i];
        final next = kChoiceOptionPalette[(i + 1) % kChoiceOptionPalette.length];
        expect(cycleChoicePaletteColor(current), equals(next));
      }
    });
  });

  group('ChoiceFieldValue model', () {
    test('empty ChoiceFieldValue has no optionIds and no other', () {
      const value = ChoiceFieldValue();
      expect(value.optionIds, isEmpty);
      expect(value.other, isNull);
    });

    test('ChoiceFieldValue holds optionIds', () {
      const value = ChoiceFieldValue(optionIds: {'opt-1', 'opt-2'});
      expect(value.optionIds, containsAll(['opt-1', 'opt-2']));
      expect(value.other, isNull);
    });

    test('ChoiceFieldValue holds other free text', () {
      const value = ChoiceFieldValue(
        optionIds: {'opt-1'},
        other: 'something custom',
      );
      expect(value.optionIds, contains('opt-1'));
      expect(value.other, equals('something custom'));
    });

    test('ChoiceFieldValue equality', () {
      const a = ChoiceFieldValue(optionIds: {'x'}, other: 'y');
      const b = ChoiceFieldValue(optionIds: {'x'}, other: 'y');
      expect(a, equals(b));
    });
  });
}
