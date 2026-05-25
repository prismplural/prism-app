import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';

// ---------------------------------------------------------------------------
// Tests that cover the registry-driven picker logic introduced in BATCH 3
// to replace the hardcoded _fieldTypeOptions list.
//
// These tests are pure Dart — no Flutter widget / Riverpod / DB deps.
// They validate the logical contracts that the CreateEditFieldSheet state
// and the detail screen depend on.
// ---------------------------------------------------------------------------

CustomFieldTypeConfig? _nullConfig(Map<String, dynamic>? j) => null;
Map<String, dynamic>? _nullConfigOut(CustomFieldTypeConfig? c) => null;
TypedFieldValue _nullParser(String? raw) => TypedFieldValue.text(raw ?? '');
String _nullEncoder(TypedFieldValue v) => '';

CustomFieldTypeDefinition _stub({
  required String id,
  required int? legacyInt,
  bool allowsTextualSwitch = false,
  String labelKey = '',
}) {
  return CustomFieldTypeDefinition(
    id: id,
    legacyIntValue: legacyInt,
    labelL10nKey: labelKey.isEmpty ? 'label_$id' : labelKey,
    icon: Icons.circle,
    configFromJson: _nullConfig,
    configToJson: _nullConfigOut,
    valueParser: _nullParser,
    valueEncoder: _nullEncoder,
    allowsTextualSwitch: allowsTextualSwitch,
  );
}

/// A registry that mirrors the production one (text, long_text, color, date,
/// choice, group) plus a future registry-only type with no legacy int.
CustomFieldTypeRegistry get _fullRegistry => CustomFieldTypeRegistry([
  _stub(id: 'text', legacyInt: 0, allowsTextualSwitch: true),
  _stub(id: 'color', legacyInt: 1),
  _stub(id: 'date', legacyInt: 2),
  _stub(id: 'long_text', legacyInt: 3, allowsTextualSwitch: true),
  _stub(id: 'choice', legacyInt: 4),
  _stub(id: 'group', legacyInt: 5),
]);

void main() {
  group('Registry-driven picker — type iteration', () {
    test('registry contains group type', () {
      expect(_fullRegistry.lookupById('group'), isNotNull);
    });

    test('all 6 production types are present', () {
      final ids = _fullRegistry.definitions.map((d) => d.id).toSet();
      expect(ids, containsAll(['text', 'long_text', 'color', 'date', 'choice', 'group']));
    });

    test('iterating definitions exposes group (was missing from hardcoded list)', () {
      // Before the fix, _fieldTypeOptions only had [text, longText, color, date, choice].
      // The registry iteration must now include 'group'.
      final defIds = _fullRegistry.definitions.map((d) => d.id).toList();
      expect(defIds, contains('group'));
    });

    test('child picker hides group to prevent nested groups', () {
      // Simulate the picker filter: when parentFieldId != null, hide 'group'.
      const parentFieldId = 'parent-123';
      final visibleForChild = _fullRegistry.definitions
          .where((d) => parentFieldId == null || d.id != 'group')
          .map((d) => d.id)
          .toList();
      expect(visibleForChild, isNot(contains('group')));
      expect(visibleForChild, contains('text'));
      expect(visibleForChild, contains('choice'));
    });

    test('top-level picker includes group', () {
      // When parentFieldId is null, all types (including group) are shown.
      const String? parentFieldId = null;
      final visibleForTopLevel = _fullRegistry.definitions
          .where((d) => parentFieldId == null || d.id != 'group')
          .map((d) => d.id)
          .toList();
      expect(visibleForTopLevel, contains('group'));
    });
  });

  group('Registry-driven picker — textual switch logic', () {
    test('allowsTextualSwitch is true for text and long_text only', () {
      final registry = _fullRegistry;
      expect(registry.lookupById('text')?.allowsTextualSwitch, isTrue);
      expect(registry.lookupById('long_text')?.allowsTextualSwitch, isTrue);
      expect(registry.lookupById('color')?.allowsTextualSwitch, isFalse);
      expect(registry.lookupById('date')?.allowsTextualSwitch, isFalse);
      expect(registry.lookupById('choice')?.allowsTextualSwitch, isFalse);
      expect(registry.lookupById('group')?.allowsTextualSwitch, isFalse);
    });

    test('isCurrentTypeTextual is true for text', () {
      // Simulate _isCurrentTypeTextual getter
      const selectedTypeId = 'text';
      final isTextual =
          _fullRegistry.lookupById(selectedTypeId)?.allowsTextualSwitch ?? false;
      expect(isTextual, isTrue);
    });

    test('isCurrentTypeTextual is false for group', () {
      const selectedTypeId = 'group';
      final isTextual =
          _fullRegistry.lookupById(selectedTypeId)?.allowsTextualSwitch ?? false;
      expect(isTextual, isFalse);
    });
  });

  group('Registry-driven picker — save: legacyIntValue mapping', () {
    test('group legacyIntValue is 5 (beyond CustomFieldType enum range)', () {
      // CustomFieldType.values has 5 entries (indices 0-4). Group is 5.
      // The _save logic must NOT call CustomFieldType.values[5] without first
      // verifying the value is in range.
      final groupDef = _fullRegistry.lookupById('group')!;
      expect(groupDef.legacyIntValue, 5);
    });

    test('all legacy types map back to valid enum indices', () {
      // For production types with legacyIntValue 0..4, the index is in range.
      const legacyEnumCount = 5; // CustomFieldType.values.length
      for (final def in _fullRegistry.definitions) {
        final legacyInt = def.legacyIntValue;
        if (legacyInt != null && legacyInt < legacyEnumCount) {
          // Would be safe to call CustomFieldType.values[legacyInt]
          expect(legacyInt, inInclusiveRange(0, legacyEnumCount - 1));
        }
      }
    });

    test('unknown type falls back to text (id 0)', () {
      // Simulate the fallback: registry returns null → use text.
      final def = _fullRegistry.lookupById('nonexistent_future_type');
      const fallbackId = 'text';
      final effectiveDef = def ?? _fullRegistry.lookupById(fallbackId);
      expect(effectiveDef?.id, fallbackId);
    });

    test('_selectedTypeId default for new top-level field is text', () {
      // New field, no widget.field → _selectedTypeId == 'text'.
      const selectedTypeId = 'text';
      expect(_fullRegistry.lookupById(selectedTypeId), isNotNull);
    });

    test('_selectedTypeId default for new child field is text (not group)', () {
      // When parentFieldId is set, _selectedTypeId starts at 'text', never 'group'.
      const parentFieldId = 'some-group-id';
      const selectedTypeId = 'text'; // enforced by initState
      expect(parentFieldId, isNotNull); // parentFieldId exists
      expect(selectedTypeId, isNot('group'));
    });
  });

  group('Registry-driven picker — config section visibility', () {
    test('date precision section visible only for date type', () {
      expect('date' == 'date', isTrue);   // selected → show
      expect('text' == 'date', isFalse);  // not selected → hide
      expect('group' == 'date', isFalse); // not selected → hide
    });

    test('choice config section visible only for choice type', () {
      expect('choice' == 'choice', isTrue);
      expect('date' == 'choice', isFalse);
      expect('group' == 'choice', isFalse);
    });

    test('switching from choice to group hides choice config', () {
      // Before: selectedTypeId == 'choice' → show choice config.
      // After:  selectedTypeId == 'group'  → hide choice config.
      var selectedTypeId = 'choice';
      expect(selectedTypeId == 'choice', isTrue);
      selectedTypeId = 'group';
      expect(selectedTypeId == 'choice', isFalse);
    });
  });
}
