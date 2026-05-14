import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/services/error_reporting_service.dart';
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/data/mappers/member_group_entry_mapper.dart';
import 'package:prism_plurality/domain/models/group_sort_mode.dart';
import 'package:prism_plurality/domain/models/group_sort_state.dart';
import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/domain/models/member_group_entry.dart'
    as domain;

import '../../helpers/mapper_test_helpers.dart';

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // MemberGroupMapper
  // ══════════════════════════════════════════════════════════════════════════

  group('MemberGroupMapper', () {
    final now = DateTime(2026, 3, 20, 12, 0);

    test('toDomain maps all fields correctly', () {
      final row = makeDbMemberGroup(
        id: 'g-1',
        name: 'Protectors',
        description: 'Safety crew',
        colorHex: '#FF0000',
        emoji: '🛡️',
        displayOrder: 3,
        parentGroupId: 'parent-group',
      );

      final model = MemberGroupMapper.toDomain(row);
      expect(model.id, 'g-1');
      expect(model.name, 'Protectors');
      expect(model.description, 'Safety crew');
      expect(model.colorHex, '#FF0000');
      expect(model.emoji, '🛡️');
      expect(model.displayOrder, 3);
      expect(model.parentGroupId, 'parent-group');
      expect(model.createdAt, now);
    });

    test('toDomain handles null optional fields', () {
      final row = makeDbMemberGroup(
        description: null,
        colorHex: null,
        emoji: null,
        parentGroupId: null,
      );

      final model = MemberGroupMapper.toDomain(row);
      expect(model.description, isNull);
      expect(model.colorHex, isNull);
      expect(model.emoji, isNull);
      expect(model.parentGroupId, isNull);
    });

    test('toCompanion preserves all fields', () {
      final model = domain.MemberGroup(
        id: 'g-2',
        name: 'Littles',
        description: 'Young parts',
        colorHex: '#00FF00',
        emoji: '🧸',
        displayOrder: 5,
        parentGroupId: 'root-group',
        createdAt: now,
      );

      final companion = MemberGroupMapper.toCompanion(model);
      expect(companion.id.value, 'g-2');
      expect(companion.name.value, 'Littles');
      expect(companion.description.value, 'Young parts');
      expect(companion.colorHex.value, '#00FF00');
      expect(companion.emoji.value, '🧸');
      expect(companion.displayOrder.value, 5);
      expect(companion.parentGroupId.value, 'root-group');
      expect(companion.createdAt.value, now);
    });

    test('round-trip preserves data', () {
      final original = domain.MemberGroup(
        id: 'rt-1',
        name: 'Round Trip',
        description: 'Testing',
        colorHex: '#AABBCC',
        emoji: '🔄',
        displayOrder: 2,
        parentGroupId: null,
        createdAt: now,
      );

      final companion = MemberGroupMapper.toCompanion(original);
      final row = db.MemberGroupRow(
        id: companion.id.value,
        name: companion.name.value,
        description: companion.description.value,
        colorHex: companion.colorHex.value,
        emoji: companion.emoji.value,
        displayOrder: companion.displayOrder.value,
        parentGroupId: companion.parentGroupId.value,
        groupType: companion.groupType.value,
        filterRules: companion.filterRules.value,
        createdAt: companion.createdAt.value,
        isDeleted: false,
        syncSuppressed: false,
        sortState: companion.sortState.value,
      );

      final restored = MemberGroupMapper.toDomain(row);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.description, original.description);
      expect(restored.colorHex, original.colorHex);
      expect(restored.emoji, original.emoji);
      expect(restored.displayOrder, original.displayOrder);
      expect(restored.parentGroupId, original.parentGroupId);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // MemberGroupEntryMapper
  // ══════════════════════════════════════════════════════════════════════════

  group('MemberGroupEntryMapper', () {
    test('toDomain maps all fields', () {
      const row = db.MemberGroupEntryRow(
        id: 'entry-1',
        groupId: 'group-1',
        memberId: 'member-1',
        isDeleted: false,
        pendingPkOp: 'none',
      );

      final model = MemberGroupEntryMapper.toDomain(row);
      expect(model.id, 'entry-1');
      expect(model.groupId, 'group-1');
      expect(model.memberId, 'member-1');
    });

    test('toCompanion preserves all fields', () {
      const model = domain.MemberGroupEntry(
        id: 'entry-2',
        groupId: 'group-2',
        memberId: 'member-2',
      );

      final companion = MemberGroupEntryMapper.toCompanion(model);
      expect(companion.id.value, 'entry-2');
      expect(companion.groupId.value, 'group-2');
      expect(companion.memberId.value, 'member-2');
    });

    test('round-trip preserves data', () {
      const original = domain.MemberGroupEntry(
        id: 'rt-entry',
        groupId: 'g-rt',
        memberId: 'm-rt',
      );

      final companion = MemberGroupEntryMapper.toCompanion(original);
      final row = db.MemberGroupEntryRow(
        id: companion.id.value,
        groupId: companion.groupId.value,
        memberId: companion.memberId.value,
        isDeleted: false,
        pendingPkOp: 'none',
      );

      final restored = MemberGroupEntryMapper.toDomain(row);
      expect(restored.id, original.id);
      expect(restored.groupId, original.groupId);
      expect(restored.memberId, original.memberId);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // MemberGroup domain model
  // ══════════════════════════════════════════════════════════════════════════

  group('MemberGroup domain model', () {
    test('constructs with required fields only', () {
      final group = domain.MemberGroup(
        id: 'g-min',
        name: 'Minimal',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(group.id, 'g-min');
      expect(group.name, 'Minimal');
      expect(group.description, isNull);
      expect(group.colorHex, isNull);
      expect(group.emoji, isNull);
      expect(group.displayOrder, 0);
      expect(group.parentGroupId, isNull);
    });

    test('copyWith works correctly', () {
      final group = domain.MemberGroup(
        id: 'g-copy',
        name: 'Original',
        createdAt: DateTime(2026, 1, 1),
      );
      final updated = group.copyWith(name: 'Updated', displayOrder: 5);
      expect(updated.name, 'Updated');
      expect(updated.displayOrder, 5);
      expect(updated.id, 'g-copy'); // unchanged
    });

    test('JSON round-trip', () {
      final group = domain.MemberGroup(
        id: 'g-json',
        name: 'JSON Test',
        description: 'desc',
        colorHex: '#123456',
        emoji: '🎯',
        displayOrder: 1,
        parentGroupId: 'parent',
        createdAt: DateTime(2026, 3, 20),
      );

      // Round-trip via a real JSON string so nested freezed objects
      // (sortState) are normalized to Map<String, dynamic> before being
      // re-parsed. The generated `toJson` writes nested freezed values
      // as-is, which is fine for jsonEncode but not for direct fromJson.
      final json = jsonDecode(jsonEncode(group.toJson()))
          as Map<String, dynamic>;
      final restored = domain.MemberGroup.fromJson(json);
      expect(restored.id, group.id);
      expect(restored.name, group.name);
      expect(restored.description, group.description);
      expect(restored.colorHex, group.colorHex);
      expect(restored.emoji, group.emoji);
      expect(restored.displayOrder, group.displayOrder);
      expect(restored.parentGroupId, group.parentGroupId);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // MemberGroupMapper sort_state cases
  // ══════════════════════════════════════════════════════════════════════════

  group('MemberGroupMapper sort_state', () {
    // The ErrorReportingService is a process-wide singleton. Snapshot the
    // pre-test error count so warn-emission assertions are robust to other
    // tests in the same process having pushed entries first.
    late int baselineErrorCount;
    setUp(() {
      baselineErrorCount =
          ErrorReportingService.instance.errors.length;
    });

    int warningsEmittedSinceBaseline() {
      final entries = ErrorReportingService.instance.errors;
      var count = 0;
      for (var i = baselineErrorCount; i < entries.length; i++) {
        if (entries[i].severity == ErrorSeverity.warning) count++;
      }
      return count;
    }

    domain.MemberGroup decodeWithSortState(String sortStateJson) {
      final row = makeDbMemberGroup(sortState: sortStateJson);
      return MemberGroupMapper.toDomain(row);
    }

    domain.MemberGroup roundTrip(GroupSortState state) {
      final original = domain.MemberGroup(
        id: 'rt',
        name: 'rt',
        createdAt: DateTime(2026, 1, 1),
        sortState: state,
      );
      final companion = MemberGroupMapper.toCompanion(original);
      final row = makeDbMemberGroup(
        id: companion.id.value,
        sortState: companion.sortState.value,
      );
      return MemberGroupMapper.toDomain(row);
    }

    test('round-trips every mode with empty manualOrder', () {
      for (final mode in GroupSortMode.values) {
        final restored = roundTrip(
          GroupSortState(mode: mode, manualOrder: const []),
        );
        expect(restored.sortState.mode, mode);
        expect(restored.sortState.manualOrder, isEmpty);
      }
      expect(warningsEmittedSinceBaseline(), 0);
    });

    test('round-trips manualOrder of length 0, 1, 50, 1000', () {
      for (final length in [0, 1, 50, 1000]) {
        final order = List.generate(length, (i) => 'entry-$i');
        final restored = roundTrip(
          GroupSortState(
            mode: GroupSortMode.manual,
            manualOrder: order,
          ),
        );
        expect(restored.sortState.manualOrder.length, length);
        expect(restored.sortState.manualOrder, order);
      }
      expect(warningsEmittedSinceBaseline(), 0);
    });

    test('decode of unknown mode int falls back to manual', () {
      final restored = decodeWithSortState('{"mode": 99, "order": []}');
      expect(restored.sortState.mode, GroupSortMode.manual);
      expect(restored.sortState.manualOrder, isEmpty);
      // Unknown int is forward-compatible — NOT a decode failure.
      expect(warningsEmittedSinceBaseline(), 0);
    });

    test('decode of non-JSON falls back to manualEmpty + warn', () {
      final restored = decodeWithSortState('not json');
      expect(restored.sortState, GroupSortState.manualEmpty);
      expect(warningsEmittedSinceBaseline(), 1);
    });

    test('decode of JSON array (not object) falls back + warn', () {
      final restored = decodeWithSortState('[]');
      expect(restored.sortState, GroupSortState.manualEmpty);
      expect(warningsEmittedSinceBaseline(), 1);
    });

    test('decode of object missing "order" key falls back + warn', () {
      final restored = decodeWithSortState('{"mode": 1}');
      expect(restored.sortState, GroupSortState.manualEmpty);
      expect(warningsEmittedSinceBaseline(), 1);
    });

    test('decode dedupes duplicate ids in order, preserving first occurrence',
        () {
      final restored = decodeWithSortState(
        jsonEncode({
          'mode': 0,
          'order': ['a', 'a', 'b'],
        }),
      );
      expect(restored.sortState.mode, GroupSortMode.manual);
      expect(restored.sortState.manualOrder, ['a', 'b']);
      expect(warningsEmittedSinceBaseline(), 0);
    });

    test('decode of mixed-type order array falls back + warn', () {
      final restored = decodeWithSortState('{"mode": 0, "order": [1, "b"]}');
      expect(restored.sortState, GroupSortState.manualEmpty);
      expect(warningsEmittedSinceBaseline(), 1);
    });

    // P1.1 — strict mode type. Wrong-type mode (string, null, double, bool)
    // must be rejected as garbage; only unknown *ints* are forward-compat.
    test('decode of string-type mode falls back + warn', () {
      final restored =
          decodeWithSortState('{"mode": "nameAsc", "order": []}');
      expect(restored.sortState, GroupSortState.manualEmpty);
      expect(warningsEmittedSinceBaseline(), 1);
    });

    test('decode of null-type mode falls back + warn', () {
      final restored = decodeWithSortState('{"mode": null, "order": []}');
      expect(restored.sortState, GroupSortState.manualEmpty);
      expect(warningsEmittedSinceBaseline(), 1);
    });

    test('decode of double-type mode falls back + warn', () {
      final restored = decodeWithSortState('{"mode": 1.5, "order": []}');
      expect(restored.sortState, GroupSortState.manualEmpty);
      expect(warningsEmittedSinceBaseline(), 1);
    });

    test('decode of bool-type mode falls back + warn', () {
      final restored = decodeWithSortState('{"mode": true, "order": []}');
      expect(restored.sortState, GroupSortState.manualEmpty);
      expect(warningsEmittedSinceBaseline(), 1);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // sanitizeSortStateForEmission
  // ══════════════════════════════════════════════════════════════════════════

  group('sanitizeSortStateForEmission', () {
    late int baselineErrorCount;
    setUp(() {
      baselineErrorCount =
          ErrorReportingService.instance.errors.length;
    });

    int warningsEmittedSinceBaseline() {
      final entries = ErrorReportingService.instance.errors;
      var count = 0;
      for (var i = baselineErrorCount; i < entries.length; i++) {
        if (entries[i].severity == ErrorSeverity.warning) count++;
      }
      return count;
    }

    test('valid input returns string byte-for-byte unchanged, no warn', () {
      const input = '{"mode":0,"order":["a","b"]}';
      final out = sanitizeSortStateForEmission(input, contextId: 'g1');
      expect(out, input);
      expect(warningsEmittedSinceBaseline(), 0);
    });

    test('invalid JSON returns manualEmpty encoding + warn', () {
      final out = sanitizeSortStateForEmission(
        'not-json-garbage',
        contextId: 'g1',
      );
      expect(out, '{"mode":0,"order":[]}');
      expect(warningsEmittedSinceBaseline(), 1);
    });

    test('wrong-type mode returns manualEmpty encoding + warn', () {
      final out = sanitizeSortStateForEmission(
        '{"mode":"nameAsc","order":[]}',
        contextId: 'g1',
      );
      expect(out, '{"mode":0,"order":[]}');
      expect(warningsEmittedSinceBaseline(), 1);
    });
  });
}
