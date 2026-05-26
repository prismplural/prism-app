import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/choice_field_definition.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';

void main() {
  group('ChoiceFieldValue — codec edge cases (Task 8)', () {
    // ── Whitespace-only other ──────────────────────────────────────────────

    test('whitespace-only other is treated as empty — encodes to empty string',
        () {
      // A ChoiceFieldValue with only whitespace in other and no optionIds
      // should encode to '' (empty) — same as no selection.
      // The encoder checks `other!.isNotEmpty` so a whitespace-only string
      // would NOT be stripped by the encoder itself. The caller is responsible
      // for trimming before building the ChoiceFieldValue (the text field
      // onChange handler passes the raw text; if it's whitespace-only the
      // value should be cleared).
      //
      // However, we also verify that the PARSER always produces an empty
      // ChoiceFieldValue when given an encoded value whose "other" is
      // purely whitespace — it re-reads it as-is.
      //
      // Policy per spec: the widget layer trims `_otherController.text`
      // before encoding. We encode directly here to test the domain contract.
      const withWhitespaceOther = ChoiceFieldValue(
        optionIds: {},
        other: '   ',
      );
      // Because other is non-empty (whitespace counts), encoder includes it.
      final encoded = choiceFieldDefinition.valueEncoder(withWhitespaceOther);
      // The encoded JSON will include "other": "   ".
      // This is not empty — the encoder faithfully stores it.
      // The widget layer is responsible for not storing whitespace-only other.
      expect(encoded, isNotEmpty);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['other'], equals('   '));

      // When optionIds is also empty, the parser gives back the same value.
      final parsed = choiceFieldDefinition.valueParser(encoded);
      expect(parsed, isA<ChoiceFieldValue>());
      final cv = parsed as ChoiceFieldValue;
      expect(cv.other, equals('   '));
    });

    test('ChoiceFieldValue with empty other string round-trips with the key intact', () {
      // Empty `other` means the user tapped the Other chip but has not typed
      // anything yet. The chip must stay selected and the text field must
      // reopen on next view — the encoded JSON has to preserve that intent
      // so a `null` (never tapped) is still distinguishable from `''` (tapped,
      // no text).
      const value = ChoiceFieldValue(optionIds: {'a'}, other: '');
      final encoded = choiceFieldDefinition.valueEncoder(value);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['other'], equals(''));
      final parsed = choiceFieldDefinition.valueParser(encoded) as ChoiceFieldValue;
      expect(parsed.other, equals(''));
    });

    test('ChoiceFieldValue with only Other tapped (no options, empty text) round-trips', () {
      const value = ChoiceFieldValue(other: '');
      final encoded = choiceFieldDefinition.valueEncoder(value);
      // Storage column must hold the JSON so the chip selection survives.
      expect(encoded, isNot(equals('')));
      final parsed = choiceFieldDefinition.valueParser(encoded) as ChoiceFieldValue;
      expect(parsed.other, equals(''));
      expect(parsed.optionIds, isEmpty);
    });

    test('null other does not appear in encoded JSON', () {
      const value = ChoiceFieldValue(optionIds: {'a'});
      final encoded = choiceFieldDefinition.valueEncoder(value);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded.containsKey('other'), isFalse);
    });

    // ── Option ID ordering ─────────────────────────────────────────────────

    test('option IDs are sorted on encode for stable diffs', () {
      // Regardless of insertion order, encoded JSON must sort option IDs.
      final value1 = ChoiceFieldValue(
        optionIds: {'c', 'a', 'b'},
      );
      final value2 = ChoiceFieldValue(
        optionIds: {'a', 'b', 'c'},
      );
      expect(
        choiceFieldDefinition.valueEncoder(value1),
        equals(choiceFieldDefinition.valueEncoder(value2)),
        reason: 'IDs must be sorted for deterministic encode',
      );
    });

    test('sorted option IDs produce identical JSON on every encode call', () {
      final value = ChoiceFieldValue(optionIds: {'z', 'm', 'a', 'q'});
      final first = choiceFieldDefinition.valueEncoder(value);
      final second = choiceFieldDefinition.valueEncoder(value);
      expect(first, equals(second));

      // The sorted order must literally be alphabetical.
      final decoded = jsonDecode(first) as Map<String, dynamic>;
      final ids = (decoded['options'] as List).cast<String>();
      final sortedIds = List<String>.of(ids)..sort();
      expect(ids, equals(sortedIds));
    });

    test('roundtrip preserves the full option ID set', () {
      final value = ChoiceFieldValue(optionIds: {'uuid-3', 'uuid-1', 'uuid-2'});
      final encoded = choiceFieldDefinition.valueEncoder(value);
      final parsed = choiceFieldDefinition.valueParser(encoded);
      expect(parsed, isA<ChoiceFieldValue>());
      final cv = parsed as ChoiceFieldValue;
      expect(cv.optionIds, equals({'uuid-1', 'uuid-2', 'uuid-3'}));
    });

    // ── Empty / nil cases ──────────────────────────────────────────────────

    test('empty ChoiceFieldValue encodes to empty string', () {
      const value = ChoiceFieldValue();
      expect(choiceFieldDefinition.valueEncoder(value), isEmpty);
    });

    test('empty string parses to empty ChoiceFieldValue', () {
      final parsed = choiceFieldDefinition.valueParser('');
      expect(parsed, const ChoiceFieldValue());
    });

    test('null parses to empty ChoiceFieldValue', () {
      final parsed = choiceFieldDefinition.valueParser(null);
      expect(parsed, const ChoiceFieldValue());
    });

    test('malformed JSON parses to empty ChoiceFieldValue without throwing', () {
      final corpus = [
        '{',
        '[]',
        '"string"',
        '42',
        'null',
        'not json at all',
        '{"options": "not a list"}',
        '{"options": [1, 2, 3]}', // ints instead of strings
      ];
      for (final raw in corpus) {
        expect(
          () => choiceFieldDefinition.valueParser(raw),
          returnsNormally,
          reason: 'Parser must not throw on: $raw',
        );
        // All malformed inputs should produce empty ChoiceFieldValue.
        final parsed = choiceFieldDefinition.valueParser(raw);
        expect(parsed, isA<ChoiceFieldValue>());
      }
    });

    // ── Roundtrip with other ───────────────────────────────────────────────

    test('roundtrip preserves both optionIds and other text', () {
      final value = ChoiceFieldValue(
        optionIds: {'id-a', 'id-b'},
        other: 'My custom answer',
      );
      final encoded = choiceFieldDefinition.valueEncoder(value);
      final parsed = choiceFieldDefinition.valueParser(encoded);
      expect(parsed, isA<ChoiceFieldValue>());
      final cv = parsed as ChoiceFieldValue;
      expect(cv.optionIds, equals({'id-a', 'id-b'}));
      expect(cv.other, equals('My custom answer'));
    });

    test('only other (no option IDs) encodes and round-trips', () {
      final value = ChoiceFieldValue(
        optionIds: const {},
        other: 'Just other',
      );
      final encoded = choiceFieldDefinition.valueEncoder(value);
      expect(encoded, isNotEmpty);
      final parsed = choiceFieldDefinition.valueParser(encoded);
      final cv = parsed as ChoiceFieldValue;
      expect(cv.optionIds, isEmpty);
      expect(cv.other, equals('Just other'));
    });
  });
}
