import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/data/mappers/member_group_mapper.dart';
import 'package:prism_plurality/data/mappers/member_group_entry_mapper.dart';
import 'package:prism_plurality/domain/models/member_group.dart' as domain;
import 'package:prism_plurality/domain/models/member_group_entry.dart' as domain;

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
        createdAt: companion.createdAt.value,
        isDeleted: false,
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

      final json = group.toJson();
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
}
