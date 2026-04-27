import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/sync_bootstrap.dart';
import 'package:prism_plurality/core/sync/sync_schema.dart';

/// Guards the invariant that every entity declared in [prismSyncSchema] has a
/// matching `_<camelCase>Entity(...)` builder registered in
/// `drift_sync_adapter.dart`, and vice versa.
///
/// CRDT metadata (HLC, dirty flags, pending ops) lives in the Rust sync
/// engine — the Dart side has no schema column to catch drift. If a new
/// synced entity is added to [prismSyncSchema] without registering an
/// adapter builder, remote changes for that entity will never land in the
/// local Drift DB (silent desync). If a builder is registered without a
/// schema entry, the Rust engine will never emit changes for it.
void main() {
  test('prismSyncSchema uses only Rust-supported field types', () {
    const supportedTypes = {
      'String',
      'Int',
      'Real',
      'Bool',
      'DateTime',
      'Blob',
    };
    final schema = jsonDecode(prismSyncSchema) as Map<String, dynamic>;
    final entities = schema['entities'] as Map<String, dynamic>;

    final unsupported = <String, String>{};
    for (final entity in entities.entries) {
      final fields =
          ((entity.value as Map<String, dynamic>)['fields']
                  as Map<String, dynamic>)
              .cast<String, dynamic>();
      for (final field in fields.entries) {
        final type = field.value as String;
        if (!supportedTypes.contains(type)) {
          unsupported['${entity.key}.${field.key}'] = type;
        }
      }
    }

    expect(
      unsupported,
      isEmpty,
      reason:
          'prismSyncSchema declared field types that Rust SyncSchema cannot '
          'parse: $unsupported',
    );
  });

  test('every prismSyncSchema entity is registered in drift_sync_adapter', () {
    final schema = jsonDecode(prismSyncSchema) as Map<String, dynamic>;
    final entities = (schema['entities'] as Map<String, dynamic>).keys.toSet();

    final adapter = File(
      'lib/core/sync/drift_sync_adapter.dart',
    ).readAsStringSync();

    // Registered builders always take `(db, quarantine, ...)`. Anchoring on
    // the `(db,` prefix avoids matching prose mentions like `_fooEntity()`
    // in the file's doc comment.
    // Registered builders always take `(db, ...)` as the first arg. Allow
    // whitespace/newlines before `db,` since some call sites wrap arguments.
    // Anchoring on `db,` avoids matching prose mentions like `_fooEntity()`.
    final builderRe = RegExp(r'_([a-zA-Z0-9]+)Entity\(\s*db,');
    final registered = builderRe
        .allMatches(adapter)
        .map((m) => _camelToSnake(m.group(1)!))
        .toSet();

    final schemaMissingBuilder = entities.difference(registered);
    final builderMissingSchema = registered.difference(entities);

    expect(
      schemaMissingBuilder,
      isEmpty,
      reason:
          'Entities in prismSyncSchema have no matching _<name>Entity builder '
          'in drift_sync_adapter.dart — remote changes will be silently dropped: '
          '$schemaMissingBuilder',
    );
    expect(
      builderMissingSchema,
      isEmpty,
      reason:
          '_<name>Entity builders in drift_sync_adapter.dart have no matching '
          'entry in prismSyncSchema — these entities will never sync: '
          '$builderMissingSchema',
    );
  });

  test('bootstrap covers every synced entity', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = buildSyncAdapterWithCompletion(db).adapter;
    final queries = bootstrapTableQueries(db);

    final schema = jsonDecode(prismSyncSchema) as Map<String, dynamic>;
    final entities = (schema['entities'] as Map<String, dynamic>).keys;

    final missing = <String>[];
    for (final entity in entities) {
      if (adapter.entityForTable(entity) == null) continue;
      if (!queries.containsKey(entity)) missing.add(entity);
    }

    expect(
      missing,
      isEmpty,
      reason:
          'bootstrapTableQueries is missing entries for synced entities; '
          'first-device bootstrap will silently skip them: $missing',
    );
  });

  test(
    'toSyncFields keys match prismSyncSchema fields for every entity',
    () async {
      final schema = jsonDecode(prismSyncSchema) as Map<String, dynamic>;
      final schemaEntities = schema['entities'] as Map<String, dynamic>;

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Insert one representative row per synced table. Most columns have
      // Drift defaults; we supply the bare minimum required to satisfy
      // NOT NULL.
      await _seedDummyRows(db);

      final adapter = buildSyncAdapterWithCompletion(db).adapter;

      final mismatches = <String, String>{};
      for (final entry in schemaEntities.entries) {
        final entityName = entry.key;
        final schemaFields =
            ((entry.value as Map<String, dynamic>)['fields']
                    as Map<String, dynamic>)
                .keys
                .toSet();

        final entity = adapter.entities.firstWhere(
          (e) => e.tableName == entityName,
          orElse: () => throw StateError(
            'No adapter builder for $entityName (caught by other parity test)',
          ),
        );

        final row = await _readDummyRow(db, entityName);
        if (row == null) {
          mismatches[entityName] = 'no dummy row found in test seed';
          continue;
        }
        final fields = entity.toSyncFields(row).keys.toSet();

        final missingFromAdapter = schemaFields.difference(fields);
        final missingFromSchema = fields.difference(schemaFields);
        if (missingFromAdapter.isNotEmpty || missingFromSchema.isNotEmpty) {
          mismatches[entityName] =
              'schema-only=$missingFromAdapter, adapter-only=$missingFromSchema';
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason:
            'Per-entity field drift between prismSyncSchema and adapter '
            'toSyncFields. schema-only fields are silently not emitted; '
            'adapter-only fields are silently dropped by the engine.\n'
            '$mismatches',
      );
    },
  );

  test(
    'toSyncFields values are compatible with prismSyncSchema field types',
    () async {
      final schema = jsonDecode(prismSyncSchema) as Map<String, dynamic>;
      final schemaEntities = schema['entities'] as Map<String, dynamic>;

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await _seedDummyRows(db);
      final adapter = buildSyncAdapterWithCompletion(db).adapter;

      final mismatches = <String, String>{};
      for (final entry in schemaEntities.entries) {
        final entityName = entry.key;
        final schemaFields =
            ((entry.value as Map<String, dynamic>)['fields']
                    as Map<String, dynamic>)
                .cast<String, dynamic>();
        final entity = adapter.entities.firstWhere(
          (e) => e.tableName == entityName,
          orElse: () => throw StateError(
            'No adapter builder for $entityName (caught by other parity test)',
          ),
        );

        final row = await _readDummyRow(db, entityName);
        if (row == null) {
          mismatches[entityName] = 'no dummy row found in test seed';
          continue;
        }

        final fields = entity.toSyncFields(row);
        for (final field in schemaFields.entries) {
          final fieldName = field.key;
          if (!fields.containsKey(fieldName)) continue;
          final value = fields[fieldName];
          if (value == null) continue;

          final declaredType = field.value as String;
          final mismatch = _schemaTypeMismatch(declaredType, value);
          if (mismatch != null) {
            mismatches['$entityName.$fieldName'] = mismatch;
          }
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason:
            'Adapter toSyncFields emitted values incompatible with '
            'prismSyncSchema field types: $mismatches',
      );
    },
  );
}

String? _schemaTypeMismatch(String declaredType, Object value) {
  switch (declaredType) {
    case 'String':
      return value is String
          ? null
          : 'expected String, got ${value.runtimeType}';
    case 'Int':
      return value is int ? null : 'expected Int, got ${value.runtimeType}';
    case 'Real':
      if (value is num && value.isFinite) return null;
      return 'expected finite Real, got ${value.runtimeType}';
    case 'Bool':
      return value is bool ? null : 'expected Bool, got ${value.runtimeType}';
    case 'DateTime':
      if (value is! String) {
        return 'expected DateTime string, got ${value.runtimeType}';
      }
      return DateTime.tryParse(value) == null
          ? 'expected parseable DateTime string, got $value'
          : null;
    case 'Blob':
      if (value is! String) {
        return 'expected base64 Blob string, got ${value.runtimeType}';
      }
      try {
        base64Decode(value);
        return null;
      } catch (_) {
        return 'expected base64 Blob string';
      }
    default:
      return 'unknown schema type $declaredType';
  }
}

Future<void> _seedDummyRows(AppDatabase db) async {
  final now = DateTime.utc(2026, 1, 1);

  await db
      .into(db.members)
      .insert(
        MembersCompanion.insert(
          id: 'm1',
          name: 'Test Member',
          createdAt: now,
          avatarImageData: Value(Uint8List.fromList([1, 2, 3])),
        ),
      );

  await db
      .into(db.frontingSessions)
      .insert(FrontingSessionsCompanion.insert(id: 's1', startTime: now));

  await db
      .into(db.conversations)
      .insert(
        ConversationsCompanion.insert(
          id: 'c1',
          createdAt: now,
          lastActivityAt: now,
        ),
      );

  await db
      .into(db.chatMessages)
      .insert(
        ChatMessagesCompanion.insert(
          id: 'msg1',
          content: 'hi',
          timestamp: now,
          conversationId: 'c1',
        ),
      );

  // System settings has a 'singleton' row; insert explicitly with the id set.
  await db
      .into(db.systemSettingsTable)
      .insert(
        SystemSettingsTableCompanion.insert(
          id: const Value('singleton'),
          wakeSuggestionAfterHours: const Value(7.25),
          systemAvatarData: Value(Uint8List.fromList([4, 5, 6])),
        ),
      );

  await db
      .into(db.polls)
      .insert(PollsCompanion.insert(id: 'p1', question: 'q?', createdAt: now));

  await db
      .into(db.pollOptions)
      .insert(
        PollOptionsCompanion.insert(id: 'po1', pollId: 'p1', optionText: 'opt'),
      );

  await db
      .into(db.pollVotes)
      .insert(
        PollVotesCompanion.insert(
          id: 'pv1',
          pollOptionId: 'po1',
          memberId: 'm1',
          votedAt: now,
        ),
      );

  await db
      .into(db.habits)
      .insert(
        HabitsCompanion.insert(
          id: 'h1',
          name: 'habit',
          createdAt: now,
          modifiedAt: now,
        ),
      );

  await db
      .into(db.habitCompletions)
      .insert(
        HabitCompletionsCompanion.insert(
          id: 'hc1',
          habitId: 'h1',
          completedAt: now,
          createdAt: now,
          modifiedAt: now,
        ),
      );

  await db
      .into(db.conversationCategories)
      .insert(
        ConversationCategoriesCompanion.insert(
          id: 'cc1',
          name: 'cat',
          createdAt: now,
          modifiedAt: now,
        ),
      );

  await db
      .into(db.reminders)
      .insert(
        RemindersCompanion.insert(
          id: 'r1',
          name: 'remind',
          message: 'msg',
          createdAt: now,
          modifiedAt: now,
        ),
      );

  await db
      .into(db.memberGroups)
      .insert(
        MemberGroupsCompanion.insert(id: 'g1', name: 'group', createdAt: now),
      );

  // member_group_entries: pk_group_uuid / pk_member_uuid are emitted
  // *conditionally* via `fields['key'] = ...` only when present on the row.
  // Seed both so the parity test sees them in toSyncFields output.
  await db
      .into(db.memberGroupEntries)
      .insert(
        MemberGroupEntriesCompanion.insert(
          id: 'mge1',
          groupId: 'g1',
          memberId: 'm1',
          pkGroupUuid: const Value('pk-group-uuid'),
          pkMemberUuid: const Value('pk-member-uuid'),
        ),
      );

  await db
      .into(db.customFields)
      .insert(
        CustomFieldsCompanion.insert(
          id: 'cf1',
          name: 'field',
          fieldType: 0,
          createdAt: now,
        ),
      );

  await db
      .into(db.customFieldValues)
      .insert(
        CustomFieldValuesCompanion.insert(
          id: 'cfv1',
          customFieldId: 'cf1',
          memberId: 'm1',
          value: 'v',
        ),
      );

  await db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          id: 'n1',
          title: 't',
          body: 'b',
          date: now,
          createdAt: now,
          modifiedAt: now,
        ),
      );

  await db
      .into(db.frontSessionComments)
      .insert(
        FrontSessionCommentsCompanion.insert(
          id: 'fsc1',
          sessionId: 's1',
          body: 'b',
          timestamp: now,
          createdAt: now,
        ),
      );

  await db
      .into(db.friends)
      .insert(
        FriendsCompanion.insert(
          id: 'f1',
          displayName: 'friend',
          publicKeyHex: 'deadbeef',
          createdAt: now,
          pairwiseSecret: Value(Uint8List.fromList([7, 8, 9])),
          pinnedIdentity: Value(Uint8List.fromList([10, 11, 12])),
        ),
      );

  await db
      .into(db.mediaAttachments)
      .insert(MediaAttachmentsCompanion.insert(id: 'ma1'));
}

Future<dynamic> _readDummyRow(AppDatabase db, String tableName) async {
  switch (tableName) {
    case 'members':
      return (db.select(db.members)..limit(1)).getSingle();
    case 'fronting_sessions':
      return (db.select(db.frontingSessions)..limit(1)).getSingle();
    case 'conversations':
      return (db.select(db.conversations)..limit(1)).getSingle();
    case 'chat_messages':
      return (db.select(db.chatMessages)..limit(1)).getSingle();
    case 'system_settings':
      return (db.select(db.systemSettingsTable)..limit(1)).getSingle();
    case 'polls':
      return (db.select(db.polls)..limit(1)).getSingle();
    case 'poll_options':
      return (db.select(db.pollOptions)..limit(1)).getSingle();
    case 'poll_votes':
      return (db.select(db.pollVotes)..limit(1)).getSingle();
    case 'habits':
      return (db.select(db.habits)..limit(1)).getSingle();
    case 'habit_completions':
      return (db.select(db.habitCompletions)..limit(1)).getSingle();
    case 'conversation_categories':
      return (db.select(db.conversationCategories)..limit(1)).getSingle();
    case 'reminders':
      return (db.select(db.reminders)..limit(1)).getSingle();
    case 'member_groups':
      return (db.select(db.memberGroups)..limit(1)).getSingle();
    case 'member_group_entries':
      return (db.select(db.memberGroupEntries)..limit(1)).getSingle();
    case 'custom_fields':
      return (db.select(db.customFields)..limit(1)).getSingle();
    case 'custom_field_values':
      return (db.select(db.customFieldValues)..limit(1)).getSingle();
    case 'notes':
      return (db.select(db.notes)..limit(1)).getSingle();
    case 'front_session_comments':
      return (db.select(db.frontSessionComments)..limit(1)).getSingle();
    case 'friends':
      return (db.select(db.friends)..limit(1)).getSingle();
    case 'media_attachments':
      return (db.select(db.mediaAttachments)..limit(1)).getSingle();
    default:
      return null;
  }
}

String _camelToSnake(String camel) {
  final buf = StringBuffer();
  for (var i = 0; i < camel.length; i++) {
    final c = camel[i];
    final isUpper = c == c.toUpperCase() && c != c.toLowerCase();
    if (isUpper && i > 0) buf.write('_');
    buf.write(c.toLowerCase());
  }
  return buf.toString();
}
