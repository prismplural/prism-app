import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';

void main() {
  test('sync schema exposes PK member_group_entries fields', () {
    final schema = jsonDecode(prismSyncSchema) as Map<String, dynamic>;
    final entities = schema['entities'] as Map<String, dynamic>;
    final memberGroupEntries =
        entities['member_group_entries'] as Map<String, dynamic>;
    final fields = memberGroupEntries['fields'] as Map<String, dynamic>;

    expect(fields.keys, containsAll(['pk_group_uuid', 'pk_member_uuid']));
    expect(fields['pk_group_uuid'], 'String');
    expect(fields['pk_member_uuid'], 'String');
  });

  test(
    'member_groups: full synced field set round-trips through adapter',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final groupsEntity = _entityFor(db, 'member_groups');
      final createdAt = DateTime.utc(2026, 4, 18, 12);
      final lastSeen = DateTime.utc(2026, 4, 19, 9, 30);

      await groupsEntity.applyFields('g-full', {
        'name': 'Core',
        'description': 'system group',
        'color_hex': '#ff00aa',
        'emoji': '🧩',
        'display_order': 7,
        'parent_group_id': 'parent-1',
        'group_type': 2,
        'filter_rules': '{"mode":"all"}',
        'created_at': createdAt.toIso8601String(),
        'pluralkit_id': 'abcde',
        'pluralkit_uuid': 'pk-g-uuid-1',
        'last_seen_from_pk_at': lastSeen.toIso8601String(),
        'is_deleted': false,
      });

      final row = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('g-full'))).getSingle();
      expect(row.name, 'Core');
      expect(row.description, 'system group');
      expect(row.colorHex, '#ff00aa');
      expect(row.emoji, '🧩');
      expect(row.displayOrder, 7);
      expect(row.parentGroupId, 'parent-1');
      expect(row.groupType, 2);
      expect(row.filterRules, '{"mode":"all"}');
      expect(row.pluralkitId, 'abcde');
      expect(row.pluralkitUuid, 'pk-g-uuid-1');
      expect(row.lastSeenFromPkAt, isNotNull);

      final encoded = groupsEntity.toSyncFields(row);
      expect(encoded.keys.toSet(), {
        'name',
        'description',
        'color_hex',
        'emoji',
        'display_order',
        'parent_group_id',
        'group_type',
        'filter_rules',
        'created_at',
        'pluralkit_id',
        'pluralkit_uuid',
        'last_seen_from_pk_at',
        'is_deleted',
      });
    },
  );

  test('member_groups: canonical PK sync id materializes a row', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final groupsEntity = _entityFor(db, 'member_groups');
    final createdAt = DateTime.utc(2026, 4, 18, 12);

    await groupsEntity.applyFields('pk-group:pk-g-uuid-1', {
      'name': 'Imported',
      'display_order': 1,
      'group_type': 0,
      'created_at': createdAt.toIso8601String(),
      'pluralkit_uuid': 'pk-g-uuid-1',
      'is_deleted': false,
    });

    final row = await (db.select(
      db.memberGroups,
    )..where((t) => t.id.equals('pk-group:pk-g-uuid-1'))).getSingle();
    expect(row.pluralkitUuid, 'pk-g-uuid-1');
    expect(row.name, 'Imported');

    final readBack = await groupsEntity.readRow('pk-group:pk-g-uuid-1');
    expect(readBack?['pluralkit_uuid'], 'pk-g-uuid-1');
  });

  test('member_groups: canonical PK sync id updates existing linked row '
      'via pluralkit_uuid', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final groupsEntity = _entityFor(db, 'member_groups');
    final createdAt = DateTime.utc(2026, 4, 18, 12);

    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: 'legacy-local-id',
            name: 'Legacy',
            createdAt: createdAt,
            pluralkitUuid: const Value('pk-g-uuid-1'),
          ),
        );

    await groupsEntity.applyFields('pk-group:pk-g-uuid-1', {
      'name': 'Canonical Update',
      'description': 'updated',
      'display_order': 4,
      'group_type': 2,
      'created_at': createdAt.toIso8601String(),
      'pluralkit_uuid': 'pk-g-uuid-1',
      'is_deleted': false,
    });

    final rows = await (db.select(
      db.memberGroups,
    )..where((t) => t.pluralkitUuid.equals('pk-g-uuid-1'))).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'legacy-local-id');
    expect(rows.single.name, 'Canonical Update');
    expect(rows.single.description, 'updated');

    final readBack = await groupsEntity.readRow('pk-group:pk-g-uuid-1');
    expect(readBack?['name'], 'Canonical Update');
    expect(readBack?['description'], 'updated');
  });

  test('member_groups: applyFields does NOT record an alias for the local row '
      'id when it differs from canonical', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _ensurePkGroupPhase1RuntimeSchema(db);

    final groupsEntity = _entityFor(db, 'member_groups');
    final createdAt = DateTime.utc(2026, 4, 18, 12);
    const pkUuid = 'pk-g-uuid-cascade';

    // Seed a local row whose id uses the importer's hyphen form
    // ("pk-group-$uuid"), distinct from the canonical ("pk-group:$uuid").
    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: 'pk-group-$pkUuid',
            name: 'Local',
            createdAt: createdAt,
            pluralkitUuid: const Value(pkUuid),
          ),
        );

    // Apply a remote canonical op for the same PK UUID. The incoming
    // entity id matches canonical, so no alias should be recorded for it;
    // critically, no alias should be recorded for the device's own local
    // row id either (this is the C1 fix).
    await groupsEntity.applyFields('pk-group:$pkUuid', {
      'name': 'Remote Canonical',
      'display_order': 1,
      'group_type': 0,
      'created_at': createdAt.toIso8601String(),
      'pluralkit_uuid': pkUuid,
      'is_deleted': false,
    });

    final aliases = await db
        .customSelect('SELECT legacy_entity_id FROM pk_group_sync_aliases')
        .get();
    expect(aliases, isEmpty);
  });

  test(
    'member_groups: applyFields still records an alias for a genuinely-legacy '
    'incoming entity id',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _ensurePkGroupPhase1RuntimeSchema(db);

      final groupsEntity = _entityFor(db, 'member_groups');
      final createdAt = DateTime.utc(2026, 4, 18, 12);
      const pkUuid = 'pk-g-uuid-legacy';

      // Pre-seed a local row under the importer's hyphen form id.
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'pk-group-$pkUuid',
              name: 'Local',
              createdAt: createdAt,
              pluralkitUuid: const Value(pkUuid),
            ),
          );

      // Apply a remote op with a *genuinely legacy* entity id. This is the
      // mixed-fleet pre-cutover case the adapter still needs to handle:
      // the incoming id is neither canonical nor the receiving device's
      // local row id, so recording an alias for it is safe and necessary.
      await groupsEntity.applyFields('random-legacy-entity-id', {
        'name': 'Remote Legacy',
        'display_order': 1,
        'group_type': 0,
        'created_at': createdAt.toIso8601String(),
        'pluralkit_uuid': pkUuid,
        'is_deleted': false,
      });

      final aliases = await db
          .customSelect(
            'SELECT legacy_entity_id, canonical_entity_id, pk_group_uuid '
            'FROM pk_group_sync_aliases',
          )
          .get();
      expect(aliases, hasLength(1));
      expect(
        aliases.single.data['legacy_entity_id'],
        'random-legacy-entity-id',
      );
      expect(aliases.single.data['canonical_entity_id'], 'pk-group:$pkUuid');
      expect(aliases.single.data['pk_group_uuid'], pkUuid);
    },
  );

  test(
    'member_groups: alias id resolves reads but deletes only the exact legacy row',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _ensurePkGroupPhase1RuntimeSchema(db);
      await db.customStatement('DROP INDEX idx_member_groups_pluralkit_uuid');

      final groupsEntity = _entityFor(db, 'member_groups');
      final createdAt = DateTime.utc(2026, 4, 18, 12);

      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'winner-local-id',
              name: 'Winner',
              createdAt: createdAt,
              pluralkitUuid: const Value('pk-g-uuid-1'),
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'legacy-entity-id',
              name: 'Loser',
              createdAt: createdAt,
              pluralkitUuid: const Value('pk-g-uuid-1'),
              isDeleted: const Value(true),
            ),
          );

      await db.pkGroupSyncAliasesDao.upsertAlias(
        legacyEntityId: 'legacy-entity-id',
        pkGroupUuid: 'pk-g-uuid-1',
        canonicalEntityId: 'pk-group:pk-g-uuid-1',
      );

      final readBack = await groupsEntity.readRow('legacy-entity-id');
      expect(readBack?['name'], 'Winner');
      expect(readBack?['pluralkit_uuid'], 'pk-g-uuid-1');

      await groupsEntity.hardDelete('legacy-entity-id');
      final winner = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('winner-local-id'))).getSingleOrNull();
      expect(winner, isNotNull);
      expect(winner!.isDeleted, isFalse);

      final loser = await (db.select(
        db.memberGroups,
      )..where((t) => t.id.equals('legacy-entity-id'))).getSingleOrNull();
      expect(loser, isNull);
    },
  );

  test(
    'member_group_entries: legacy local-id round-trip stays unchanged',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final entriesEntity = _entityFor(db, 'member_group_entries');

      await entriesEntity.applyFields('entry-1', {
        'group_id': 'group-1',
        'member_id': 'member-1',
        'is_deleted': false,
      });

      final row = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('entry-1'))).getSingle();
      expect(row.groupId, 'group-1');
      expect(row.memberId, 'member-1');
      expect(row.isDeleted, isFalse);

      final encoded = entriesEntity.toSyncFields(row);
      expect(encoded['group_id'], 'group-1');
      expect(encoded['member_id'], 'member-1');
      expect(encoded['is_deleted'], false);
      if (encoded.containsKey('pk_group_uuid')) {
        expect(encoded['pk_group_uuid'], isNull);
      }
      if (encoded.containsKey('pk_member_uuid')) {
        expect(encoded['pk_member_uuid'], isNull);
      }
    },
  );

  test('member_group_entries: PK UUID payload resolves local ids and persists '
      'PK refs when runtime schema supports them', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _ensurePkGroupPhase1RuntimeSchema(db);

    final entriesEntity = _entityFor(db, 'member_group_entries');
    final now = DateTime.utc(2026, 4, 18, 12);

    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(
            id: 'member-local-1',
            name: 'Alice',
            createdAt: now,
            pluralkitUuid: const Value('pk-member-1'),
          ),
        );
    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: 'group-local-1',
            name: 'Core',
            createdAt: now,
            pluralkitUuid: const Value('pk-group-1'),
          ),
        );

    await entriesEntity.applyFields('entry-v2', {
      'pk_group_uuid': 'pk-group-1',
      'pk_member_uuid': 'pk-member-1',
      'is_deleted': false,
    });

    final row = await (db.select(
      db.memberGroupEntries,
    )..where((t) => t.id.equals('entry-v2'))).getSingle();
    expect(row.groupId, 'group-local-1');
    expect(row.memberId, 'member-local-1');

    final rawPkFields = await db
        .customSelect(
          '''
            SELECT pk_group_uuid, pk_member_uuid
            FROM member_group_entries
            WHERE id = ?
            ''',
          variables: const [Variable<String>('entry-v2')],
        )
        .getSingle();
    expect(rawPkFields.data['pk_group_uuid'], 'pk-group-1');
    expect(rawPkFields.data['pk_member_uuid'], 'pk-member-1');

    final readBack = await entriesEntity.readRow('entry-v2');
    expect(readBack?['group_id'], 'group-local-1');
    expect(readBack?['member_id'], 'member-local-1');
    expect(readBack?['pk_group_uuid'], 'pk-group-1');
    expect(readBack?['pk_member_uuid'], 'pk-member-1');
  });

  test(
    'member_group_entries: PK UUID resolution wins over sender-local hints',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _ensurePkGroupPhase1RuntimeSchema(db);

      final entriesEntity = _entityFor(db, 'member_group_entries');
      final now = DateTime.utc(2026, 4, 18, 12);

      await db
          .into(db.members)
          .insert(
            MembersCompanion.insert(
              id: 'member-local-correct',
              name: 'Alice',
              createdAt: now,
              pluralkitUuid: const Value('pk-member-1'),
            ),
          );
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'group-local-correct',
              name: 'Core',
              createdAt: now,
              pluralkitUuid: const Value('pk-group-1'),
            ),
          );

      await entriesEntity.applyFields('entry-pk-wins', {
        'pk_group_uuid': 'pk-group-1',
        'pk_member_uuid': 'pk-member-1',
        'group_id': 'sender-local-wrong-group',
        'member_id': 'sender-local-wrong-member',
        'is_deleted': false,
      });

      final row = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('entry-pk-wins'))).getSingle();
      expect(row.groupId, 'group-local-correct');
      expect(row.memberId, 'member-local-correct');
      expect(row.pkGroupUuid, 'pk-group-1');
      expect(row.pkMemberUuid, 'pk-member-1');
    },
  );

  test(
    'member_group_entries: PK UUID payload with non-null legacy hints defers '
    'when PK UUID does not resolve',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _ensurePkGroupPhase1RuntimeSchema(db);

      final entriesEntity = _entityFor(db, 'member_group_entries');

      // Plan §5.2: once a PK UUID field is present on the payload,
      // sender-local `group_id` / `member_id` are compatibility hints only.
      // They must not be used as authoritative cross-device fallbacks when
      // PK UUID resolution misses — the op must defer into the retry queue.
      await entriesEntity.applyFields('entry-h1', {
        'pk_group_uuid': 'missing-group-uuid',
        'pk_member_uuid': 'missing-member-uuid',
        'group_id': 'sender-local-group',
        'member_id': 'sender-local-member',
        'is_deleted': false,
      });

      // No local row inserted under the sender's local ids.
      final applied = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('entry-h1'))).getSingleOrNull();
      expect(applied, isNull);

      // Deferred op persisted for later replay.
      final deferred = await db
          .customSelect(
            '''
            SELECT entity_type, entity_id, fields_json, reason
            FROM pk_group_entry_deferred_sync_ops
            WHERE id = ?
            ''',
            variables: const [
              Variable<String>('member_group_entries:entry-h1'),
            ],
          )
          .getSingle();
      expect(deferred.data['entity_type'], 'member_group_entries');
      expect(deferred.data['entity_id'], 'entry-h1');
      expect(
        deferred.data['fields_json'],
        contains('"pk_group_uuid":"missing-group-uuid"'),
      );
      expect(
        deferred.data['reason'],
        contains('unresolved_pk_refs:group:missing-group-uuid'),
      );
      expect(deferred.data['reason'], contains('member:missing-member-uuid'));
    },
  );

  test('member_group_entries: unresolved PK UUID payload defers when '
      'deferred-op table exists', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _ensurePkGroupPhase1RuntimeSchema(db);

    final entriesEntity = _entityFor(db, 'member_group_entries');

    await entriesEntity.applyFields('entry-deferred', {
      'pk_group_uuid': 'missing-group',
      'pk_member_uuid': 'missing-member',
      'is_deleted': false,
    });

    final applied = await (db.select(
      db.memberGroupEntries,
    )..where((t) => t.id.equals('entry-deferred'))).getSingleOrNull();
    expect(applied, isNull);

    final deferred = await db
        .customSelect(
          '''
            SELECT entity_type, entity_id, fields_json, reason
            FROM pk_group_entry_deferred_sync_ops
            WHERE id = ?
            ''',
          variables: const [
            Variable<String>('member_group_entries:entry-deferred'),
          ],
        )
        .getSingle();
    expect(deferred.data['entity_type'], 'member_group_entries');
    expect(deferred.data['entity_id'], 'entry-deferred');
    expect(
      deferred.data['fields_json'],
      contains('"pk_group_uuid":"missing-group"'),
    );
    expect(
      deferred.data['reason'],
      contains('unresolved_pk_refs:group:missing-group'),
    );
    expect(deferred.data['reason'], contains('member:missing-member'));
  });

  test('member_group_entries: deferred PK entry replays when missing group '
      'arrives later', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _ensurePkGroupPhase1RuntimeSchema(db);

    final entriesEntity = _entityFor(db, 'member_group_entries');
    final groupsEntity = _entityFor(db, 'member_groups');
    final now = DateTime.utc(2026, 4, 18, 12);

    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(
            id: 'member-local-1',
            name: 'Alice',
            createdAt: now,
            pluralkitUuid: const Value('pk-member-1'),
          ),
        );

    await entriesEntity.applyFields('entry-replay-group', {
      'pk_group_uuid': 'pk-group-1',
      'pk_member_uuid': 'pk-member-1',
      'is_deleted': false,
    });

    expect(
      await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('entry-replay-group'))).getSingleOrNull(),
      isNull,
    );

    await groupsEntity.applyFields('pk-group:pk-group-1', {
      'name': 'Imported',
      'display_order': 0,
      'group_type': 0,
      'created_at': now.toIso8601String(),
      'pluralkit_uuid': 'pk-group-1',
      'is_deleted': false,
    });

    final applied = await (db.select(
      db.memberGroupEntries,
    )..where((t) => t.id.equals('entry-replay-group'))).getSingle();
    expect(applied.groupId, 'pk-group:pk-group-1');
    expect(applied.memberId, 'member-local-1');

    final deferred = await db
        .customSelect(
          '''
            SELECT id
            FROM pk_group_entry_deferred_sync_ops
            WHERE id = ?
          ''',
          variables: [
            const Variable<String>('member_group_entries:entry-replay-group'),
          ],
        )
        .getSingleOrNull();
    expect(deferred, isNull);
  });

  test('member_group_entries: deferred PK entry replays when missing member '
      'arrives later', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _ensurePkGroupPhase1RuntimeSchema(db);

    final entriesEntity = _entityFor(db, 'member_group_entries');
    final groupsEntity = _entityFor(db, 'member_groups');
    final membersEntity = _entityFor(db, 'members');
    final now = DateTime.utc(2026, 4, 18, 12);

    await groupsEntity.applyFields('pk-group:pk-group-1', {
      'name': 'Imported',
      'display_order': 0,
      'group_type': 0,
      'created_at': now.toIso8601String(),
      'pluralkit_uuid': 'pk-group-1',
      'is_deleted': false,
    });

    await entriesEntity.applyFields('entry-replay-member', {
      'pk_group_uuid': 'pk-group-1',
      'pk_member_uuid': 'pk-member-1',
      'is_deleted': false,
    });

    expect(
      await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('entry-replay-member'))).getSingleOrNull(),
      isNull,
    );

    await membersEntity.applyFields('member-local-1', {
      'name': 'Alice',
      'emoji': '❔',
      'is_active': true,
      'created_at': now.toIso8601String(),
      'display_order': 0,
      'is_admin': false,
      'custom_color_enabled': false,
      'markdown_enabled': false,
      'pluralkit_sync_ignored': false,
      'pluralkit_uuid': 'pk-member-1',
      'is_deleted': false,
    });

    final applied = await (db.select(
      db.memberGroupEntries,
    )..where((t) => t.id.equals('entry-replay-member'))).getSingle();
    expect(applied.groupId, 'pk-group:pk-group-1');
    expect(applied.memberId, 'member-local-1');

    final deferred = await db
        .customSelect(
          '''
            SELECT id
            FROM pk_group_entry_deferred_sync_ops
            WHERE id = ?
          ''',
          variables: [
            const Variable<String>('member_group_entries:entry-replay-member'),
          ],
        )
        .getSingleOrNull();
    expect(deferred, isNull);
  });

  test(
    'member_group_entries: hard delete cancels queued deferred replay',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await _ensurePkGroupPhase1RuntimeSchema(db);

      final entriesEntity = _entityFor(db, 'member_group_entries');
      final groupsEntity = _entityFor(db, 'member_groups');
      final membersEntity = _entityFor(db, 'members');
      final now = DateTime.utc(2026, 4, 18, 12);

      await entriesEntity.applyFields('entry-cancelled', {
        'pk_group_uuid': 'pk-group-1',
        'pk_member_uuid': 'pk-member-1',
        'is_deleted': false,
      });

      await entriesEntity.hardDelete('entry-cancelled');

      final deferred = await db
          .customSelect(
            '''
            SELECT id
            FROM pk_group_entry_deferred_sync_ops
            WHERE id = ?
            ''',
            variables: const [
              Variable<String>('member_group_entries:entry-cancelled'),
            ],
          )
          .getSingleOrNull();
      expect(deferred, isNull);

      await groupsEntity.applyFields('pk-group:pk-group-1', {
        'name': 'Imported',
        'display_order': 0,
        'group_type': 0,
        'created_at': now.toIso8601String(),
        'pluralkit_uuid': 'pk-group-1',
        'is_deleted': false,
      });
      await membersEntity.applyFields('member-local-1', {
        'name': 'Alice',
        'emoji': '❔',
        'is_active': true,
        'created_at': now.toIso8601String(),
        'display_order': 0,
        'is_admin': false,
        'custom_color_enabled': false,
        'markdown_enabled': false,
        'pluralkit_sync_ignored': false,
        'pluralkit_uuid': 'pk-member-1',
        'is_deleted': false,
      });

      final applied = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('entry-cancelled'))).getSingleOrNull();
      expect(applied, isNull);
    },
  );

  test('member_group_entries: canonical hard delete cancels legacy deferred PK '
      'edge siblings', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _ensurePkGroupPhase1RuntimeSchema(db);

    final entriesEntity = _entityFor(db, 'member_group_entries');
    final canonicalEntryId = _deterministicPkEntryId(
      'pk-group-1',
      'pk-member-1',
    );

    await db.customStatement(
      '''
        INSERT INTO pk_group_entry_deferred_sync_ops
          (id, entity_type, entity_id, fields_json, reason, created_at, retry_count)
        VALUES (?, ?, ?, ?, ?, ?, 0)
        ''',
      [
        'member_group_entries:legacy-entry-id',
        'member_group_entries',
        'legacy-entry-id',
        jsonEncode({
          'pk_group_uuid': 'pk-group-1',
          'pk_member_uuid': 'pk-member-1',
          'is_deleted': false,
        }),
        'seeded_for_test',
        DateTime.utc(2026, 4, 18, 12).millisecondsSinceEpoch,
      ],
    );

    await entriesEntity.hardDelete(canonicalEntryId);

    final deferredRows = await db.customSelect('''
            SELECT id
            FROM pk_group_entry_deferred_sync_ops
          ''').get();
    expect(deferredRows, isEmpty);
  });

  test('sync batch completion replays previously deferred PK entries when '
      'refs already exist locally', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _ensurePkGroupPhase1RuntimeSchema(db);

    final adapterWithCompletion = buildSyncAdapterWithCompletion(db);
    final now = DateTime.utc(2026, 4, 18, 12);

    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(
            id: 'member-local-1',
            name: 'Alice',
            createdAt: now,
            pluralkitUuid: const Value('pk-member-1'),
          ),
        );
    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: 'group-local-1',
            name: 'Core',
            createdAt: now,
            pluralkitUuid: const Value('pk-group-1'),
          ),
        );
    await db.customStatement(
      '''
        INSERT INTO pk_group_entry_deferred_sync_ops
          (id, entity_type, entity_id, fields_json, reason, created_at, retry_count)
        VALUES (?, ?, ?, ?, ?, ?, 0)
        ''',
      [
        'member_group_entries:entry-batch-replay',
        'member_group_entries',
        'entry-batch-replay',
        jsonEncode({
          'pk_group_uuid': 'pk-group-1',
          'pk_member_uuid': 'pk-member-1',
          'is_deleted': false,
        }),
        'seeded_for_test',
        now.millisecondsSinceEpoch,
      ],
    );

    adapterWithCompletion.beginSyncBatch();
    await adapterWithCompletion.completeSyncBatch();

    final applied = await (db.select(
      db.memberGroupEntries,
    )..where((t) => t.id.equals('entry-batch-replay'))).getSingle();
    expect(applied.groupId, 'group-local-1');
    expect(applied.memberId, 'member-local-1');

    final deferred = await db
        .customSelect(
          '''
            SELECT id
            FROM pk_group_entry_deferred_sync_ops
            WHERE id = ?
          ''',
          variables: [
            const Variable<String>('member_group_entries:entry-batch-replay'),
          ],
        )
        .getSingleOrNull();
    expect(deferred, isNull);
  });

  test('sync batch completion prefers canonical deferred PK entry ids and '
      'skips legacy siblings for the same logical edge', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _ensurePkGroupPhase1RuntimeSchema(db);

    final adapterWithCompletion = buildSyncAdapterWithCompletion(db);
    final canonicalEntryId = _deterministicPkEntryId(
      'pk-group-1',
      'pk-member-1',
    );
    final now = DateTime.utc(2026, 4, 18, 12);

    await db
        .into(db.members)
        .insert(
          MembersCompanion.insert(
            id: 'member-local-1',
            name: 'Alice',
            createdAt: now,
            pluralkitUuid: const Value('pk-member-1'),
          ),
        );
    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: 'group-local-1',
            name: 'Core',
            createdAt: now,
            pluralkitUuid: const Value('pk-group-1'),
          ),
        );

    await db.customStatement(
      '''
        INSERT INTO pk_group_entry_deferred_sync_ops
          (id, entity_type, entity_id, fields_json, reason, created_at, retry_count)
        VALUES (?, ?, ?, ?, ?, ?, 0)
        ''',
      [
        'member_group_entries:legacy-entry-id',
        'member_group_entries',
        'legacy-entry-id',
        jsonEncode({
          'pk_group_uuid': 'pk-group-1',
          'pk_member_uuid': 'pk-member-1',
          'is_deleted': false,
        }),
        'seeded_for_test',
        now.millisecondsSinceEpoch,
      ],
    );
    await db.customStatement(
      '''
        INSERT INTO pk_group_entry_deferred_sync_ops
          (id, entity_type, entity_id, fields_json, reason, created_at, retry_count)
        VALUES (?, ?, ?, ?, ?, ?, 0)
        ''',
      [
        'member_group_entries:$canonicalEntryId',
        'member_group_entries',
        canonicalEntryId,
        jsonEncode({
          'pk_group_uuid': 'pk-group-1',
          'pk_member_uuid': 'pk-member-1',
          'is_deleted': false,
        }),
        'seeded_for_test',
        now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      ],
    );

    adapterWithCompletion.beginSyncBatch();
    await adapterWithCompletion.completeSyncBatch();

    final rows = await (db.select(db.memberGroupEntries)).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, canonicalEntryId);
    expect(rows.single.groupId, 'group-local-1');
    expect(rows.single.memberId, 'member-local-1');

    final deferredRows = await db.customSelect('''
            SELECT id
            FROM pk_group_entry_deferred_sync_ops
          ''').get();
    expect(deferredRows, isEmpty);
  });

  test('sync batch completion quarantines permanently unresolved deferred PK '
      'entries after max retries', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _ensurePkGroupPhase1RuntimeSchema(db);

    final quarantine = SyncQuarantineService(db.syncQuarantineDao);
    final adapterWithCompletion = buildSyncAdapterWithCompletion(
      db,
      quarantine: quarantine,
    );
    final now = DateTime.utc(2026, 4, 18, 12);

    await db.customStatement(
      '''
        INSERT INTO pk_group_entry_deferred_sync_ops
          (id, entity_type, entity_id, fields_json, reason, created_at, retry_count)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
      [
        'member_group_entries:entry-terminal',
        'member_group_entries',
        'entry-terminal',
        jsonEncode({
          'pk_group_uuid': 'missing-group',
          'pk_member_uuid': 'missing-member',
          'is_deleted': false,
        }),
        'seeded_for_test',
        now.millisecondsSinceEpoch,
        9,
      ],
    );

    adapterWithCompletion.beginSyncBatch();
    await adapterWithCompletion.completeSyncBatch();

    final deferred = await db
        .customSelect(
          '''
            SELECT id
            FROM pk_group_entry_deferred_sync_ops
            WHERE id = ?
            ''',
          variables: const [
            Variable<String>('member_group_entries:entry-terminal'),
          ],
        )
        .getSingleOrNull();
    expect(deferred, isNull);

    final quarantineRows = await db.syncQuarantineDao.getAll();
    expect(quarantineRows, hasLength(1));
    expect(quarantineRows.single.entityType, 'member_group_entries');
    expect(quarantineRows.single.entityId, 'entry-terminal');
    expect(
      quarantineRows.single.errorMessage,
      contains('Deferred PK-backed entry exceeded max retries'),
    );
  });

  test('member_groups: duplicate PK-linked rows do not crash canonical sync '
      'apply and prefer an active row', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final groupsEntity = _entityFor(db, 'member_groups');
    final createdAt = DateTime.utc(2026, 4, 18, 12);

    await db.customStatement('DROP INDEX idx_member_groups_pluralkit_uuid');
    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: 'deleted-duplicate',
            name: 'Deleted duplicate',
            createdAt: createdAt,
            pluralkitUuid: const Value('pk-g-uuid-dup'),
            isDeleted: const Value(true),
          ),
        );
    await db
        .into(db.memberGroups)
        .insert(
          MemberGroupsCompanion.insert(
            id: 'active-duplicate',
            name: 'Active duplicate',
            createdAt: createdAt.add(const Duration(minutes: 1)),
            pluralkitUuid: const Value('pk-g-uuid-dup'),
          ),
        );

    await groupsEntity.applyFields('pk-group:pk-g-uuid-dup', {
      'name': 'Updated active row',
      'display_order': 2,
      'group_type': 0,
      'created_at': createdAt.toIso8601String(),
      'pluralkit_uuid': 'pk-g-uuid-dup',
      'is_deleted': false,
    });

    final active = await (db.select(
      db.memberGroups,
    )..where((t) => t.id.equals('active-duplicate'))).getSingle();
    final deleted = await (db.select(
      db.memberGroups,
    )..where((t) => t.id.equals('deleted-duplicate'))).getSingle();
    expect(active.name, 'Updated active row');
    expect(active.isDeleted, isFalse);
    expect(deleted.name, 'Deleted duplicate');

    final readBack = await groupsEntity.readRow('pk-group:pk-g-uuid-dup');
    expect(readBack?['name'], 'Updated active row');
  });

  test(
    'member_group_entries: toSyncFields emits PK UUIDs when row exposes them',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final entriesEntity = _entityFor(db, 'member_group_entries');
      final encoded = entriesEntity.toSyncFields(
        const _FakeMemberGroupEntryRow(
          groupId: 'group-local-1',
          memberId: 'member-local-1',
          pkGroupUuid: 'pk-group-1',
          pkMemberUuid: 'pk-member-1',
          isDeleted: false,
        ),
      );

      expect(encoded, {
        'group_id': 'group-local-1',
        'member_id': 'member-local-1',
        'pk_group_uuid': 'pk-group-1',
        'pk_member_uuid': 'pk-member-1',
        'is_deleted': false,
      });
    },
  );
}

DriftSyncEntity _entityFor(AppDatabase db, String tableName) {
  final adapter = buildSyncAdapterWithCompletion(db).adapter;
  return adapter.entities.singleWhere(
    (entity) => entity.tableName == tableName,
  );
}

Future<void> _ensurePkGroupPhase1RuntimeSchema(AppDatabase db) async {
  await _ensureColumn(db, 'member_group_entries', 'pk_group_uuid', 'TEXT');
  await _ensureColumn(db, 'member_group_entries', 'pk_member_uuid', 'TEXT');
  await _ensureColumn(
    db,
    'member_groups',
    'sync_suppressed',
    'INTEGER NOT NULL DEFAULT 0',
  );
  await _ensureColumn(db, 'member_groups', 'suspected_pk_group_uuid', 'TEXT');
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS pk_group_sync_aliases (
      legacy_entity_id TEXT NOT NULL PRIMARY KEY,
      pk_group_uuid TEXT NOT NULL,
      canonical_entity_id TEXT NOT NULL,
      created_at INTEGER NOT NULL
    )
    ''');
  await db.customStatement('''
    CREATE TABLE IF NOT EXISTS pk_group_entry_deferred_sync_ops (
      id TEXT NOT NULL PRIMARY KEY,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      fields_json TEXT NOT NULL,
      reason TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      last_retry_at INTEGER,
      retry_count INTEGER NOT NULL DEFAULT 0
    )
    ''');
}

Future<void> _ensureColumn(
  AppDatabase db,
  String tableName,
  String columnName,
  String columnDefinition,
) async {
  final columns = await db.customSelect('PRAGMA table_info($tableName)').get();
  final exists = columns
      .map((row) => row.data['name'])
      .whereType<String>()
      .contains(columnName);
  if (exists) return;

  await db.customStatement(
    'ALTER TABLE $tableName ADD COLUMN $columnName $columnDefinition',
  );
}

class _FakeMemberGroupEntryRow {
  const _FakeMemberGroupEntryRow({
    required this.groupId,
    required this.memberId,
    required this.pkGroupUuid,
    required this.pkMemberUuid,
    required this.isDeleted,
  });

  final String groupId;
  final String memberId;
  final String? pkGroupUuid;
  final String? pkMemberUuid;
  final bool isDeleted;
}

String _deterministicPkEntryId(String groupUuid, String memberUuid) {
  final digest = sha256.convert(utf8.encode('$groupUuid\u0000$memberUuid'));
  return digest.toString().substring(0, 16);
}
