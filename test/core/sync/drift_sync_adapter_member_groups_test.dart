import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

void main() {
  test('member_groups: pluralkit_id / pluralkit_uuid round-trip via JSON',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final adapter =
        buildSyncAdapterWithCompletion(db).adapter;
    final groupsEntity = adapter.entities
        .singleWhere((e) => e.tableName == 'member_groups');

    final now = DateTime.utc(2026, 4, 18, 12);

    // Encode a row with PK fields via toSyncFields by first inserting a row.
    await db.into(db.memberGroups).insert(
          MemberGroupsCompanion.insert(
            id: 'g-1',
            name: 'Core',
            createdAt: now,
            pluralkitId: const Value('abcde'),
            pluralkitUuid: const Value('pk-g-uuid-1'),
            lastSeenFromPkAt: Value(now),
          ),
        );

    final row = await (db.select(db.memberGroups)
          ..where((t) => t.id.equals('g-1')))
        .getSingle();
    final encoded = groupsEntity.toSyncFields(row);
    expect(encoded['pluralkit_id'], 'abcde');
    expect(encoded['pluralkit_uuid'], 'pk-g-uuid-1');
    // Drift rehydrates DateTime in local time; compare instants rather
    // than exact ISO strings.
    expect(
      DateTime.parse(encoded['last_seen_from_pk_at'] as String)
          .toUtc()
          .isAtSameMomentAs(now),
      isTrue,
    );

    // Decode a different entity and re-read.
    await groupsEntity.applyFields('g-2', {
      'name': 'Imported',
      'display_order': 1,
      'group_type': 0,
      'created_at': now.toIso8601String(),
      'pluralkit_id': 'zzzzz',
      'pluralkit_uuid': 'pk-g-uuid-2',
      'last_seen_from_pk_at': now.toIso8601String(),
      'is_deleted': false,
    });

    final g2 = await (db.select(db.memberGroups)
          ..where((t) => t.id.equals('g-2')))
        .getSingle();
    expect(g2.pluralkitId, 'zzzzz');
    expect(g2.pluralkitUuid, 'pk-g-uuid-2');
    expect(g2.lastSeenFromPkAt, isNotNull);
  });

  test(
      'round-trip through an old-schema decode preserves PK fields when '
      're-encoded: old clients ignore unknown fields, new-client encode '
      'still emits them',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final adapter = buildSyncAdapterWithCompletion(db).adapter;
    final groupsEntity = adapter.entities
        .singleWhere((e) => e.tableName == 'member_groups');

    final now = DateTime.utc(2026, 4, 18, 12);

    // Simulate what an old client would apply — a subset of fields without
    // the new PK columns. A new client then re-reads the row and re-encodes.
    await groupsEntity.applyFields('g-x', {
      'name': 'LegacyShape',
      'display_order': 0,
      'group_type': 0,
      'created_at': now.toIso8601String(),
      'is_deleted': false,
    });

    // A new client then applies the PK fields on top. In practice the
    // adapter applies the full row state, so required fields are still
    // present in the op payload.
    await groupsEntity.applyFields('g-x', {
      'name': 'LegacyShape',
      'display_order': 0,
      'group_type': 0,
      'created_at': now.toIso8601String(),
      'is_deleted': false,
      'pluralkit_id': 'abcde',
      'pluralkit_uuid': 'pk-g-uuid-x',
      'last_seen_from_pk_at': now.toIso8601String(),
    });

    final row = await (db.select(db.memberGroups)
          ..where((t) => t.id.equals('g-x')))
        .getSingle();
    expect(row.pluralkitId, 'abcde');
    expect(row.pluralkitUuid, 'pk-g-uuid-x');

    // Re-encoding from the local row must still emit PK fields.
    final reencoded = groupsEntity.toSyncFields(row);
    expect(reencoded['pluralkit_uuid'], 'pk-g-uuid-x');
    expect(reencoded['pluralkit_id'], 'abcde');
  });
}
