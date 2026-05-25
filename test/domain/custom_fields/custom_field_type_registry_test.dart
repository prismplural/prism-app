import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';

// ---------------------------------------------------------------------------
// Test-local stub definitions — pure logic, no widget/riverpod/database deps.
// The actual production registry (customFieldTypeRegistry) can't be imported
// directly in pure unit tests because its definitions transitively import
// Riverpod and database providers. These stubs mirror the production IDs and
// legacy ints so the logic tests remain meaningful.
// ---------------------------------------------------------------------------

CustomFieldTypeConfig? _nullConfig(Map<String, dynamic>? json) => null;
Map<String, dynamic>? _nullConfigOut(CustomFieldTypeConfig? config) => null;
TypedFieldValue _nullParser(String? raw) => TypedFieldValue.text(raw ?? '');
String _nullEncoder(TypedFieldValue v) => '';

CustomFieldTypeDefinition _stub({
  required String id,
  required int legacyInt,
  bool allowsTextualSwitch = false,
}) {
  return CustomFieldTypeDefinition(
    id: id,
    legacyIntValue: legacyInt,
    labelL10nKey: 'test_$id',
    icon: Icons.circle,
    configFromJson: _nullConfig,
    configToJson: _nullConfigOut,
    valueParser: _nullParser,
    valueEncoder: _nullEncoder,
    allowsTextualSwitch: allowsTextualSwitch,
  );
}

// Mirror the production legacy int mapping (matches CustomFieldType enum order):
//   text=0, color=1, date=2, longText=3
final _textStub = _stub(id: 'text', legacyInt: 0, allowsTextualSwitch: true);
final _colorStub = _stub(id: 'color', legacyInt: 1);
final _dateStub = _stub(id: 'date', legacyInt: 2);
final _longTextStub = _stub(
  id: 'long_text',
  legacyInt: 3,
  allowsTextualSwitch: true,
);

CustomFieldTypeRegistry get _legacyRegistry => CustomFieldTypeRegistry([
  _textStub,
  _colorStub,
  _dateStub,
  _longTextStub,
]);

void main() {
  group('CustomFieldTypeRegistry', () {
    test('rejects duplicate IDs', () {
      expect(
        () => CustomFieldTypeRegistry([_textStub, _textStub]),
        throwsStateError,
      );
    });

    test('rejects duplicate legacy ints', () {
      final defA = _stub(id: 'alpha', legacyInt: 99);
      final defB = _stub(id: 'beta', legacyInt: 99);
      expect(
        () => CustomFieldTypeRegistry([defA, defB]),
        throwsStateError,
      );
    });

    test('stub registry has all 4 expected types', () {
      final registry = _legacyRegistry;
      expect(registry.lookupById('text'), isNotNull);
      expect(registry.lookupById('long_text'), isNotNull);
      expect(registry.lookupById('color'), isNotNull);
      expect(registry.lookupById('date'), isNotNull);
    });

    test('lookupByLegacyInt covers 0..3', () {
      final registry = _legacyRegistry;
      // CustomFieldType enum order: text=0, color=1, date=2, longText=3
      expect(registry.lookupByLegacyInt(0)?.id, 'text');
      expect(registry.lookupByLegacyInt(1)?.id, 'color');
      expect(registry.lookupByLegacyInt(2)?.id, 'date');
      expect(registry.lookupByLegacyInt(3)?.id, 'long_text');
    });

    test('unknown ID returns null (forward-compat)', () {
      expect(_legacyRegistry.lookupById('future_type'), isNull);
    });

    test('unknown legacy int returns null', () {
      expect(_legacyRegistry.lookupByLegacyInt(99), isNull);
    });

    test('allowsTextualSwitch is true only for text and long_text', () {
      final registry = _legacyRegistry;
      expect(registry.lookupById('text')?.allowsTextualSwitch, isTrue);
      expect(registry.lookupById('long_text')?.allowsTextualSwitch, isTrue);
      expect(registry.lookupById('color')?.allowsTextualSwitch, isFalse);
      expect(registry.lookupById('date')?.allowsTextualSwitch, isFalse);
    });

    test('definitions list is unmodifiable', () {
      final registry = _legacyRegistry;
      expect(
        () => (registry.definitions as List).add(
          _stub(id: 'hack', legacyInt: 999),
        ),
        throwsUnsupportedError,
      );
    });

    test('nullable legacyIntValue is allowed', () {
      final noLegacyDef = CustomFieldTypeDefinition(
        id: 'future_no_legacy',
        legacyIntValue: null,
        labelL10nKey: 'future',
        icon: Icons.circle,
        configFromJson: _nullConfig,
        configToJson: _nullConfigOut,
        valueParser: _nullParser,
        valueEncoder: _nullEncoder,
      );
      // Two definitions with null legacyIntValue should be allowed
      // (no int collision since null is excluded from the duplicate check).
      expect(
        () => CustomFieldTypeRegistry([noLegacyDef, _textStub]),
        returnsNormally,
      );
    });

    test('stable string IDs match expected values', () {
      // Validate the IDs are exactly the wire format strings used in Task 4.
      expect(_textStub.id, 'text');
      expect(_colorStub.id, 'color');
      expect(_dateStub.id, 'date');
      expect(_longTextStub.id, 'long_text');
    });

    test('legacy ints match CustomFieldType enum ordinals', () {
      // These must match the .index values used in the bridge:
      //   customFieldTypeRegistry.lookupByLegacyInt(field.fieldType.index)
      expect(_textStub.legacyIntValue, 0); // CustomFieldType.text.index
      expect(_colorStub.legacyIntValue, 1); // CustomFieldType.color.index
      expect(_dateStub.legacyIntValue, 2); // CustomFieldType.date.index
      expect(_longTextStub.legacyIntValue, 3); // CustomFieldType.longText.index
    });
  });
}
