import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/custom_field_namespaces.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_plurality/core/sync/sync_quarantine.dart';
import 'package:prism_plurality/domain/models/fronting_session.dart' as domain;

class _DelayedQuarantineService extends SyncQuarantineService {
  _DelayedQuarantineService(super.dao, this.gate);

  final Completer<void> gate;

  @override
  Future<void> quarantineField({
    required String entityType,
    required String entityId,
    String? fieldName,
    required String expectedType,
    required String receivedType,
    String? receivedValue,
    String? sourceDevice,
    String? errorMessage,
  }) async {
    await gate.future;
    await super.quarantineField(
      entityType: entityType,
      entityId: entityId,
      fieldName: fieldName,
      expectedType: expectedType,
      receivedType: receivedType,
      receivedValue: receivedValue,
      sourceDevice: sourceDevice,
      errorMessage: errorMessage,
    );
  }
}

SyncEvent _eventFromChanges(List<Map<String, dynamic>> changes) {
  return SyncEvent.fromJson({'type': 'RemoteChanges', 'changes': changes});
}

const _fullRemotePayloadFixturePath =
    'test/fixtures/sync/full_remote_payloads.json';

late final List<String> _remoteCreateOrder;
late final Map<String, String> _remoteCreateIds;
late final Map<String, Map<String, dynamic>> _remoteCreatePayloads;

Future<void> _loadFullRemotePayloadFixture() async {
  final fixture =
      jsonDecode(await File(_fullRemotePayloadFixturePath).readAsString())
          as Map<String, dynamic>;

  _remoteCreateOrder = List<String>.from(fixture['order'] as List<dynamic>);
  _remoteCreateIds = Map<String, String>.from(
    fixture['ids'] as Map<String, dynamic>,
  );
  _remoteCreatePayloads = {
    for (final entry in (fixture['payloads'] as Map<String, dynamic>).entries)
      entry.key: Map<String, dynamic>.from(entry.value as Map<String, dynamic>),
  };
}

void main() {
  setUpAll(_loadFullRemotePayloadFixture);

  test(
    'quarantined field writes are tracked before sync batch completion',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final gate = Completer<void>();
      final quarantine = _DelayedQuarantineService(db.syncQuarantineDao, gate);
      final syncAdapter = buildSyncAdapterWithCompletion(
        db,
        quarantine: quarantine,
      );

      final members = syncAdapter.adapter.entities.singleWhere(
        (entity) => entity.tableName == 'members',
      );

      syncAdapter.beginSyncBatch();

      final applyFuture = members.applyFields('member-1', {
        'name': 'Ada',
        'emoji': '✨',
        'is_active': true,
        'created_at': DateTime.utc(2026, 3, 18).toIso8601String(),
        'display_order': 1,
        'is_admin': false,
        'custom_color_enabled': false,
        'bio': 123,
        'is_deleted': false,
      });

      await applyFuture;
      expect(await db.syncQuarantineDao.count(), 0);

      var batchComplete = false;
      final completeFuture = syncAdapter.completeSyncBatch();
      unawaited(completeFuture.then((_) => batchComplete = true));

      await Future<void>.delayed(Duration.zero);
      expect(batchComplete, isFalse);

      gate.complete();
      await completeFuture;

      expect(batchComplete, isTrue);
      expect(await db.syncQuarantineDao.count(), 1);
    },
  );

  group('legacy member age quarantine repair', () {
    test('restores a missing String age from an old Int mismatch', () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.members)
          .insert(
            database.MembersCompanion.insert(
              id: 'member-1',
              name: 'Ada',
              createdAt: DateTime.utc(2026, 6, 2),
            ),
          );

      final quarantine = SyncQuarantineService(db.syncQuarantineDao);
      await quarantine.quarantineField(
        entityType: 'members',
        entityId: 'member-1',
        fieldName: 'age',
        expectedType: 'int?',
        receivedType: 'String',
        receivedValue: 'twenty-ish',
        errorMessage: 'Type mismatch: expected int?, got String',
      );

      final repaired = await quarantine.repairLegacyMemberAgeStringMismatches();
      final member = await (db.select(
        db.members,
      )..where((t) => t.id.equals('member-1'))).getSingle();

      expect(repaired, 1);
      expect(member.age, 'twenty-ish');
      expect(await db.syncQuarantineDao.getAll(), isEmpty);
    });

    test('does not overwrite an age already repaired locally', () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.members)
          .insert(
            database.MembersCompanion.insert(
              id: 'member-1',
              name: 'Ada',
              age: const Value('local value'),
              createdAt: DateTime.utc(2026, 6, 2),
            ),
          );

      final quarantine = SyncQuarantineService(db.syncQuarantineDao);
      await quarantine.quarantineField(
        entityType: 'members',
        entityId: 'member-1',
        fieldName: 'age',
        expectedType: 'int?',
        receivedType: 'String',
        receivedValue: 'remote value',
        errorMessage: 'Type mismatch: expected int?, got String',
      );

      final repaired = await quarantine.repairLegacyMemberAgeStringMismatches();
      final member = await (db.select(
        db.members,
      )..where((t) => t.id.equals('member-1'))).getSingle();

      expect(repaired, 0);
      expect(member.age, 'local value');
      expect(await db.syncQuarantineDao.getAll(), hasLength(1));
    });

    test(
      'clearAll preserves a recoverable missing age before deleting rows',
      () async {
        final db = database.AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        await db
            .into(db.members)
            .insert(
              database.MembersCompanion.insert(
                id: 'member-1',
                name: 'Ada',
                createdAt: DateTime.utc(2026, 6, 2),
              ),
            );

        final quarantine = SyncQuarantineService(db.syncQuarantineDao);
        await quarantine.quarantineField(
          entityType: 'members',
          entityId: 'member-1',
          fieldName: 'age',
          expectedType: 'int?',
          receivedType: 'String',
          receivedValue: 'twenty-ish',
          errorMessage: 'Type mismatch: expected int?, got String',
        );

        await quarantine.clearAll();
        final member = await (db.select(
          db.members,
        )..where((t) => t.id.equals('member-1'))).getSingle();

        expect(member.age, 'twenty-ish');
        expect(await db.syncQuarantineDao.getAll(), isEmpty);
      },
    );
  });

  test(
    'fronting_sessions sync entity carries sleep fields and sleep_sessions is removed',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final entityNames = syncAdapter.adapter.entities
          .map((entity) => entity.tableName)
          .toSet();

      expect(entityNames, contains('fronting_sessions'));
      expect(entityNames, isNot(contains('sleep_sessions')));

      final frontingEntity = syncAdapter.adapter.entities.singleWhere(
        (entity) => entity.tableName == 'fronting_sessions',
      );
      final session = database.FrontingSession(
        id: 'sleep-1',
        startTime: DateTime(2026, 3, 18, 10),
        endTime: DateTime(2026, 3, 18, 12),
        memberId: null,
        coFronterIds: '[]',
        sessionType: domain.SessionType.sleep.index,
        quality: domain.SleepQuality.unknown.index,
        isHealthKitImport: true,
        pluralkitUuid: null,
        pkImportSource: null,
        pkFileSwitchId: null,
        isDeleted: false,
      );

      final fields = frontingEntity.toSyncFields(session);
      expect(fields['session_type'], 1);
      expect(fields['quality'], 0);
      expect(fields['is_health_kit_import'], isTrue);
      expect(fields['pk_import_source'], isNull);
      expect(fields['pk_file_switch_id'], isNull);
    },
  );

  test(
    'front_session_comments applyFields writes required session_id',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final comments = syncAdapter.adapter.entities.singleWhere(
        (entity) => entity.tableName == 'front_session_comments',
      );

      await comments.applyFields('comment-1', {
        'session_id': 'session-1',
        'body': 'hello',
        'timestamp': DateTime.utc(2026, 4, 29, 12, 1).toIso8601String(),
        'created_at': DateTime.utc(2026, 4, 29, 12, 2).toIso8601String(),
        'is_deleted': false,
      });

      final row = await (db.select(
        db.frontSessionComments,
      )..where((t) => t.id.equals('comment-1'))).getSingle();
      expect(row.sessionId, 'session-1');
      expect(row.body, 'hello');
    },
  );

  test(
    'front_session_comments applyFields quarantines missing session_id',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final quarantine = SyncQuarantineService(db.syncQuarantineDao);
      final syncAdapter = buildSyncAdapterWithCompletion(
        db,
        quarantine: quarantine,
      );
      final comments = syncAdapter.adapter.entities.singleWhere(
        (entity) => entity.tableName == 'front_session_comments',
      );

      syncAdapter.beginSyncBatch();
      await comments.applyFields('comment-1', {
        'body': 'edited body',
        'timestamp': DateTime.utc(2026, 4, 29, 12, 1).toIso8601String(),
        'created_at': DateTime.utc(2026, 4, 29, 12, 2).toIso8601String(),
        'is_deleted': false,
      });
      await syncAdapter.completeSyncBatch();

      final row = await (db.select(
        db.frontSessionComments,
      )..where((t) => t.id.equals('comment-1'))).getSingleOrNull();
      expect(row, isNull);

      final entries = await db.syncQuarantineDao.getAll();
      expect(entries, hasLength(1));
      expect(entries.single.entityType, 'front_session_comments');
      expect(entries.single.entityId, 'comment-1');
      expect(entries.single.fieldName, 'session_id');
    },
  );

  test('fronting_sessions applyFields without pk_member_ids_json preserves the '
      'local column value', () async {
    // Workstream 2 step 1 (remediation-plan-2026-04-30): a v7 receiver
    // applying a payload that omits the transitional `pk_member_ids_json`
    // field must NOT clobber whatever is on disk — that column is the
    // input to the v8 cleanup migration's PK fan-out backfill.
    final db = database.AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.frontingSessions)
        .insert(
          database.FrontingSessionsCompanion.insert(
            id: 'session-1',
            startTime: DateTime.utc(2026, 4, 29, 10),
            memberId: const Value('m1'),
            pkMemberIdsJson: const Value('["pkmem-1","pkmem-2"]'),
          ),
        );

    final syncAdapter = buildSyncAdapterWithCompletion(db);
    final sessions = syncAdapter.adapter.entities.singleWhere(
      (entity) => entity.tableName == 'fronting_sessions',
    );

    // Apply an update payload that does NOT include pk_member_ids_json.
    await sessions.applyFields('session-1', {
      'start_time': DateTime.utc(2026, 4, 29, 10).toIso8601String(),
      'session_type': 0,
      'is_health_kit_import': false,
      'is_deleted': false,
    });

    final row = await (db.select(
      db.frontingSessions,
    )..where((t) => t.id.equals('session-1'))).getSingle();
    expect(
      row.pkMemberIdsJson,
      '["pkmem-1","pkmem-2"]',
      reason:
          'omitted transitional fields must use Value.absent() in the '
          'companion so the local column survives',
    );
  });

  test('fronting_sessions applyFields writes pk_member_ids_json when the '
      'payload carries it', () async {
    final db = database.AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final syncAdapter = buildSyncAdapterWithCompletion(db);
    final sessions = syncAdapter.adapter.entities.singleWhere(
      (entity) => entity.tableName == 'fronting_sessions',
    );

    await sessions.applyFields('session-1', {
      'start_time': DateTime.utc(2026, 4, 29, 10).toIso8601String(),
      'session_type': 0,
      'member_id': 'm1',
      'is_health_kit_import': false,
      'is_deleted': false,
      'pk_member_ids_json': '["pkmem-7"]',
    });

    final row = await (db.select(
      db.frontingSessions,
    )..where((t) => t.id.equals('session-1'))).getSingle();
    expect(row.pkMemberIdsJson, '["pkmem-7"]');
  });

  test(
    'fronting_sessions toSyncFields emits pk_member_ids_json when present on '
    'the local row',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final sessions = syncAdapter.adapter.entities.singleWhere(
        (entity) => entity.tableName == 'fronting_sessions',
      );

      final row = database.FrontingSession(
        id: 'session-2',
        startTime: DateTime.utc(2026, 4, 29, 10),
        endTime: null,
        memberId: 'm1',
        coFronterIds: '[]',
        sessionType: 0,
        quality: null,
        isHealthKitImport: false,
        pluralkitUuid: null,
        pkImportSource: null,
        pkFileSwitchId: null,
        pkMemberIdsJson: '["pkmem-9"]',
        isDeleted: false,
      );

      final fields = sessions.toSyncFields(row);
      expect(fields['pk_member_ids_json'], '["pkmem-9"]');
    },
  );

  test(
    'sync applyFields can create every entity from a remote payload',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = buildSyncAdapterWithCompletion(db).adapter;
      final failures = <String, Object>{};
      expect(
        _remoteCreateOrder.toSet(),
        adapter.entities.map((entity) => entity.tableName).toSet(),
        reason:
            'The full remote payload fixture must cover every registered '
            'sync entity.',
      );

      for (final table in _remoteCreateOrder) {
        final entity = adapter.entities.singleWhere(
          (e) => e.tableName == table,
        );
        final id = _remoteCreateIds[table]!;
        final fields = Map<String, dynamic>.from(_remoteCreatePayloads[table]!);
        try {
          await entity.applyFields(id, fields);
          final row = await entity.readRow(id);
          _recordFullRemotePayloadReadBackFailures(
            failures: failures,
            table: table,
            row: row,
            fields: fields,
            nullRowMessage: 'applyFields completed but readRow returned null',
          );
        } catch (e) {
          failures[table] = e;
        }
      }

      expect(
        failures,
        isEmpty,
        reason:
            'Every synced entity must be insertable from its sync field shape. '
            'Every emitted field must also round-trip through readRow. '
            'A failure here usually means Drift has a NOT NULL local-only '
            'column that remote/snapshot apply does not populate, or an '
            'applyFields mapper silently skipped a synced field.',
      );
    },
  );

  test(
    'strict pairing apply can restore every entity from full remote payloads',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = buildSyncAdapterWithCompletion(db).adapter;
      final failures = <String, Object>{};
      final progress = <int>[];
      expect(
        _remoteCreateOrder.toSet(),
        adapter.entities.map((entity) => entity.tableName).toSet(),
        reason:
            'The strict pairing restore fixture must cover every registered '
            'sync entity.',
      );

      final event = _eventFromChanges([
        for (final table in _remoteCreateOrder)
          {
            'table': table,
            'entity_id': _remoteCreateIds[table]!,
            'is_delete': false,
            'fields': Map<String, dynamic>.from(_remoteCreatePayloads[table]!),
          },
      ]);

      final result = await applyRemoteChanges(
        db,
        adapter,
        event,
        strict: true,
        onProgress: (applied, total) {
          expect(total, _remoteCreateOrder.length);
          progress.add(applied);
        },
      );

      expect(result.rowsApplied, _remoteCreateOrder.length);
      expect(result.failedTables, isEmpty);
      expect(
        progress,
        List<int>.generate(_remoteCreateOrder.length, (i) => i + 1),
      );

      for (final table in _remoteCreateOrder) {
        final entity = adapter.entities.singleWhere(
          (e) => e.tableName == table,
        );
        final id = _remoteCreateIds[table]!;
        final fields = _remoteCreatePayloads[table]!;
        final row = await entity.readRow(id);
        _recordFullRemotePayloadReadBackFailures(
          failures: failures,
          table: table,
          row: row,
          fields: fields,
          nullRowMessage:
              'applyRemoteChanges completed but readRow returned null',
        );
      }

      expect(
        failures,
        isEmpty,
        reason:
            'The strict pairing restore path must accept the full synced '
            'field shape for every entity and round-trip every supplied '
            'field through readRow.',
      );
    },
  );

  test(
    'sync applyFields can update every existing entity with a partial payload',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = buildSyncAdapterWithCompletion(db).adapter;
      final failures = <String, Object>{};

      for (final table in _remoteCreateOrder) {
        final entity = adapter.entities.singleWhere(
          (e) => e.tableName == table,
        );
        final id = _remoteCreateIds[table]!;
        await entity.applyFields(
          id,
          Map<String, dynamic>.from(_remoteCreatePayloads[table]!),
        );
      }

      for (final table in _remoteCreateOrder) {
        final entity = adapter.entities.singleWhere(
          (e) => e.tableName == table,
        );
        final id = _remoteCreateIds[table]!;
        try {
          await entity.applyFields(id, {'is_deleted': true});
          final row = await entity.readRow(id);
          if (row?['is_deleted'] != true) {
            failures[table] = 'partial update did not set is_deleted=true';
          }
        } catch (e) {
          failures[table] = e;
        }
      }

      expect(
        failures,
        isEmpty,
        reason:
            'Remote update batches may carry only changed fields. Existing '
            'rows must accept partial sync payloads without requiring every '
            'create-time field again.',
      );
    },
  );

  test(
    'custom_field_values applyFields merges active logical row with different '
    'remote id',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = buildSyncAdapterWithCompletion(db).adapter;
      final values = adapter.entities.singleWhere(
        (entity) => entity.tableName == 'custom_field_values',
      );

      await db
          .into(db.customFieldValues)
          .insert(
            database.CustomFieldValuesCompanion.insert(
              id: 'local-random-value',
              customFieldId: 'field-1',
              memberId: 'member-1',
              value: 'local',
            ),
          );

      await values.applyFields('remote-random-value', {
        'custom_field_id': 'field-1',
        'member_id': 'member-1',
        'value': 'remote',
        'is_deleted': false,
      });

      final rows = await db.select(db.customFieldValues).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'local-random-value');
      expect(rows.single.value, 'remote');
    },
  );

  test('custom_field_values applyFields canonicalizes active logical row when '
      'remote id is deterministic', () async {
    final db = database.AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = buildSyncAdapterWithCompletion(db).adapter;
    final values = adapter.entities.singleWhere(
      (entity) => entity.tableName == 'custom_field_values',
    );
    final deterministicId = deriveCustomFieldValueId(
      customFieldId: 'field-1',
      memberId: 'member-1',
    );

    await db
        .into(db.customFieldValues)
        .insert(
          database.CustomFieldValuesCompanion.insert(
            id: 'local-random-value',
            customFieldId: 'field-1',
            memberId: 'member-1',
            value: 'local',
          ),
        );

    await values.applyFields(deterministicId, {
      'custom_field_id': 'field-1',
      'member_id': 'member-1',
      'value': 'remote',
      'is_deleted': false,
    });

    final rows = await db.select(db.customFieldValues).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, deterministicId);
    expect(rows.single.value, 'remote');
    expect(await values.readRow(deterministicId), isNotNull);
  });

  test(
    'remote tombstones for unknown rows do not abort pairing apply',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = buildSyncAdapterWithCompletion(db).adapter;

      final conversations = adapter.entities.singleWhere(
        (e) => e.tableName == 'conversations',
      );
      await conversations.applyFields('missing-conversation', {
        'is_deleted': true,
      });
      final conversation = await conversations.readRow('missing-conversation');
      expect(conversation, isNotNull);
      expect(conversation?['is_deleted'], isTrue);

      final members = adapter.entities.singleWhere(
        (e) => e.tableName == 'members',
      );
      await members.applyFields('missing-member', {
        'pluralkit_uuid': 'missing-pk-member',
        'is_deleted': true,
      });
      final member = await members.readRow('missing-member');
      expect(member, isNotNull);
      expect(member?['pluralkit_uuid'], 'missing-pk-member');
      expect(member?['is_deleted'], isTrue);

      final groups = adapter.entities.singleWhere(
        (e) => e.tableName == 'member_groups',
      );
      await groups.applyFields('pk-group:missing-pk-group', {
        'is_deleted': true,
      });
      final group = await groups.readRow('pk-group:missing-pk-group');
      expect(group, isNotNull);
      expect(group?['pluralkit_uuid'], 'missing-pk-group');
      expect(group?['is_deleted'], isTrue);

      final entries = adapter.entities.singleWhere(
        (e) => e.tableName == 'member_group_entries',
      );
      await entries.applyFields('missing-member-group-entry', {
        'is_deleted': true,
      });
      expect(await entries.readRow('missing-member-group-entry'), isNull);
    },
  );

  test('sync hardDelete removes every synced entity', () async {
    final db = database.AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = buildSyncAdapterWithCompletion(db).adapter;
    final failures = <String, Object>{};

    for (final table in _remoteCreateOrder) {
      final entity = adapter.entities.singleWhere((e) => e.tableName == table);
      final id = _remoteCreateIds[table]!;
      await entity.applyFields(
        id,
        Map<String, dynamic>.from(_remoteCreatePayloads[table]!),
      );
    }

    for (final table in _remoteCreateOrder.reversed) {
      final entity = adapter.entities.singleWhere((e) => e.tableName == table);
      final id = _remoteCreateIds[table]!;
      try {
        await entity.hardDelete(id);
        final row = await entity.readRow(id);
        if (row != null) {
          failures[table] = 'hardDelete completed but row still exists';
        }
      } catch (e) {
        failures[table] = e;
      }
    }

    expect(failures, isEmpty);
  });

  test(
    'sync hardDelete for chat_messages removes child media attachments',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = buildSyncAdapterWithCompletion(db).adapter;
      final messages = adapter.entities.singleWhere(
        (entity) => entity.tableName == 'chat_messages',
      );

      await messages.applyFields(
        'message-with-media',
        Map<String, dynamic>.from(_remoteCreatePayloads['chat_messages']!)
          ..['conversation_id'] = 'conversation-with-media',
      );
      await db
          .into(db.mediaAttachments)
          .insert(
            database.MediaAttachmentsCompanion.insert(
              id: 'attachment-for-message',
              messageId: const Value('message-with-media'),
              mediaId: const Value('media-for-message'),
              mediaType: const Value('image'),
            ),
          );

      await messages.hardDelete('message-with-media');

      expect(await messages.readRow('message-with-media'), isNull);
      expect(
        await db.mediaAttachmentsDao.getById('attachment-for-message'),
        isNull,
      );
      expect(await db.mediaAttachmentsDao.watchAllChatMedia().first, isEmpty);
    },
  );

  test(
    'sync hardDelete for empty chat_messages id preserves sentinel media',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final adapter = buildSyncAdapterWithCompletion(db).adapter;
      final messages = adapter.entities.singleWhere(
        (entity) => entity.tableName == 'chat_messages',
      );

      await db
          .into(db.mediaAttachments)
          .insert(
            database.MediaAttachmentsCompanion.insert(
              id: 'bio-media',
              messageId: const Value(''),
              memberId: const Value('member-1'),
              mediaId: const Value('bio-media-id'),
              mediaType: const Value('image'),
            ),
          );
      await db
          .into(db.mediaAttachments)
          .insert(
            database.MediaAttachmentsCompanion.insert(
              id: 'library-media',
              messageId: const Value(''),
              tag: const Value('logo'),
              mediaId: const Value('library-media-id'),
              mediaType: const Value('image'),
            ),
          );

      await messages.hardDelete('');

      expect(await db.mediaAttachmentsDao.getById('bio-media'), isNotNull);
      expect(await db.mediaAttachmentsDao.getById('library-media'), isNotNull);
    },
  );

  // ---------------------------------------------------------------------------
  // PK bidirectional sync (plan 08) — round-trip locks for new fields.
  //
  // Risk #3 from the plan: "adding columns without wiring drift_sync_adapter
  // means new fields don't sync between devices." These tests pack a row into
  // sync fields via the adapter, apply the same field map back through
  // applyFields, read the row, and assert every PK-related column round-trips
  // both when populated and when null.
  // ---------------------------------------------------------------------------

  Future<Map<String, Object?>> roundTripMember(
    database.AppDatabase db,
    database.Member input,
  ) async {
    final syncAdapter = buildSyncAdapterWithCompletion(db);
    final members = syncAdapter.adapter.entities.singleWhere(
      (e) => e.tableName == 'members',
    );

    // Seed via Drift so toSyncFields has a row to read.
    await db.into(db.members).insertOnConflictUpdate(input.toCompanion(false));

    final packed = members.toSyncFields(input);

    // Wipe and re-apply via the sync path.
    await (db.delete(db.members)..where((t) => t.id.equals(input.id))).go();
    await members.applyFields(input.id, Map<String, dynamic>.from(packed));

    final back = await members.readRow(input.id);
    return back!;
  }

  Future<Map<String, Object?>> roundTripFrontingSession(
    database.AppDatabase db,
    database.FrontingSession input,
  ) async {
    final syncAdapter = buildSyncAdapterWithCompletion(db);
    final fronting = syncAdapter.adapter.entities.singleWhere(
      (e) => e.tableName == 'fronting_sessions',
    );

    await db
        .into(db.frontingSessions)
        .insertOnConflictUpdate(input.toCompanion(false));

    final packed = fronting.toSyncFields(input);

    await (db.delete(
      db.frontingSessions,
    )..where((t) => t.id.equals(input.id))).go();
    await fronting.applyFields(input.id, Map<String, dynamic>.from(packed));

    final back = await fronting.readRow(input.id);
    return back!;
  }

  test(
    'members: PK fields round-trip through sync adapter when populated',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final member = database.Member(
        id: 'm-1',
        name: 'Ada',
        emoji: '✨',
        avatarImageData: Uint8List.fromList([1, 2, 3]),
        pkAvatarCachedUrl: 'https://example.invalid/avatar.png',
        isActive: true,
        createdAt: DateTime.utc(2026, 3, 18),
        displayOrder: 1,
        isAdmin: false,
        customColorEnabled: false,
        pluralkitUuid: 'uuid-ada',
        pluralkitId: 'ada',
        pluralkitDisplayName: 'Ada PK',
        displayName: 'Ada Lovelace',
        birthday: '1815-12-10',
        proxyTagsJson: '[{"prefix":"A:","suffix":null}]',
        pkBannerUrl: 'https://example.invalid/banner.png',
        profileHeaderSource: 0,
        profileHeaderLayout: 1,
        profileHeaderVisible: false,
        nameStyleFont: 1,
        nameStyleBold: false,
        nameStyleItalic: true,
        nameStyleColorMode: 2,
        nameStyleColorHex: '#445566',
        profileHeaderImageData: Uint8List.fromList([4, 5, 6]),
        pkBannerImageData: Uint8List.fromList([7, 8, 9]),
        pkBannerCachedUrl: 'https://example.invalid/banner.png',
        pluralkitSyncIgnored: true,
        markdownEnabled: true,
        isDeleted: false,
        isAlwaysFronting: false,
      );

      final back = await roundTripMember(db, member);
      expect(back['pluralkit_display_name'], 'Ada PK');
      expect(back['display_name'], 'Ada Lovelace');
      expect(back['birthday'], '1815-12-10');
      expect(back['proxy_tags_json'], '[{"prefix":"A:","suffix":null}]');
      expect(back['pluralkit_sync_ignored'], isTrue);
      expect(back['pluralkit_id'], 'ada');
      expect(back['pluralkit_uuid'], 'uuid-ada');
      expect(
        back['pk_avatar_cached_url'],
        'https://example.invalid/avatar.png',
      );
      expect(back['pk_banner_url'], 'https://example.invalid/banner.png');
      expect(back['profile_header_source'], 0);
      expect(back['profile_header_layout'], 1);
      expect(back['profile_header_visible'], isFalse);
      expect(back['name_style_font'], 1);
      expect(back['name_style_bold'], isFalse);
      expect(back['name_style_italic'], isTrue);
      expect(back['name_style_color_mode'], 2);
      expect(back['name_style_color_hex'], '#445566');
      expect(back['profile_header_image_data'], 'BAUG');
      expect(back['pk_banner_image_data'], 'BwgJ');
      expect(
        back['pk_banner_cached_url'],
        'https://example.invalid/banner.png',
      );
    },
  );

  test(
    'members: PK fields round-trip as null (not missing) when not set',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final member = database.Member(
        id: 'm-2',
        name: 'Bo',
        emoji: '🌱',
        isActive: true,
        createdAt: DateTime.utc(2026, 3, 18),
        displayOrder: 0,
        isAdmin: false,
        customColorEnabled: false,
        profileHeaderSource: 1,
        profileHeaderLayout: 0,
        profileHeaderVisible: true,
        nameStyleFont: 0,
        nameStyleBold: true,
        nameStyleItalic: false,
        nameStyleColorMode: 0,
        pluralkitSyncIgnored: false,
        markdownEnabled: false,
        isDeleted: false,
        isAlwaysFronting: false,
      );

      final back = await roundTripMember(db, member);
      expect(
        back.containsKey('display_name'),
        isTrue,
        reason: 'Null must be present as an explicit key, not missing',
      );
      expect(back['display_name'], isNull);
      expect(back.containsKey('birthday'), isTrue);
      expect(back['birthday'], isNull);
      expect(back.containsKey('proxy_tags_json'), isTrue);
      expect(back['proxy_tags_json'], isNull);
      expect(back.containsKey('pk_avatar_cached_url'), isTrue);
      expect(back['pk_avatar_cached_url'], isNull);
      expect(back.containsKey('pk_banner_url'), isTrue);
      expect(back['profile_header_visible'], isTrue);
      expect(back['pk_banner_url'], isNull);
      expect(back['profile_header_source'], 1);
      expect(back['profile_header_layout'], 0);
      expect(back['name_style_font'], 0);
      expect(back['name_style_bold'], isTrue);
      expect(back['name_style_italic'], isFalse);
      expect(back['name_style_color_mode'], 0);
      expect(back.containsKey('name_style_color_hex'), isTrue);
      expect(back['name_style_color_hex'], isNull);
      expect(back.containsKey('profile_header_image_data'), isTrue);
      expect(back['profile_header_image_data'], isNull);
      expect(back.containsKey('pk_banner_image_data'), isTrue);
      expect(back['pk_banner_image_data'], isNull);
      expect(back.containsKey('pk_banner_cached_url'), isTrue);
      expect(back['pk_banner_cached_url'], isNull);
      expect(back['pluralkit_sync_ignored'], isFalse);
      expect(back['pluralkit_uuid'], isNull);
      expect(back['pluralkit_id'], isNull);
      expect(back['pluralkit_display_name'], isNull);
    },
  );

  test(
    'fronting_sessions: PK file-origin metadata round-trips through sync adapter',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final session = database.FrontingSession(
        id: 'fs-pk-file-1',
        startTime: DateTime.utc(2026, 4, 29, 12),
        endTime: DateTime.utc(2026, 4, 29, 12, 30),
        memberId: 'member-1',
        coFronterIds: '[]',
        sessionType: domain.SessionType.normal.index,
        isHealthKitImport: false,
        pluralkitUuid: null,
        pkImportSource: 'file',
        pkFileSwitchId: '2026-04-29T12:00:00Z|switch-1',
        isDeleted: false,
      );

      final back = await roundTripFrontingSession(db, session);
      expect(back['pluralkit_uuid'], isNull);
      expect(back['pk_import_source'], 'file');
      expect(back['pk_file_switch_id'], '2026-04-29T12:00:00Z|switch-1');
    },
  );

  test(
    'fronting_sessions: PK file-origin metadata round-trips as null',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final session = database.FrontingSession(
        id: 'fs-native-1',
        startTime: DateTime.utc(2026, 4, 29, 12),
        memberId: 'member-1',
        coFronterIds: '[]',
        sessionType: domain.SessionType.normal.index,
        isHealthKitImport: false,
        pluralkitUuid: null,
        pkImportSource: null,
        pkFileSwitchId: null,
        isDeleted: false,
      );

      final back = await roundTripFrontingSession(db, session);
      expect(back.containsKey('pk_import_source'), isTrue);
      expect(back['pk_import_source'], isNull);
      expect(back.containsKey('pk_file_switch_id'), isTrue);
      expect(back['pk_file_switch_id'], isNull);
    },
  );

  // ---------------------------------------------------------------------------
  // DateTime UTC normalization (audit batch O)
  //
  // Drift reads DateTime columns as local time. Without `.toUtc()`, the wire
  // string has no offset/Z, so a peer in a different timezone parses it as
  // their own local time, shifting the absolute moment by the timezone delta.
  // The sync adapter must funnel every DateTime emission through the
  // _dateTimeToSyncString helper. These tests pin the contract.
  // ---------------------------------------------------------------------------

  test(
    'fronting_sessions: DateTime fields serialize as UTC (Z-suffixed)',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final fronting = syncAdapter.adapter.entities.singleWhere(
        (e) => e.tableName == 'fronting_sessions',
      );

      // Local DateTime — no UTC marker on the input.
      final localStart = DateTime(2024, 1, 1, 12);
      final localEnd = DateTime(2024, 1, 1, 14);
      final session = database.FrontingSession(
        id: 'fs-utc-1',
        startTime: localStart,
        endTime: localEnd,
        memberId: null,
        coFronterIds: '[]',
        sessionType: domain.SessionType.sleep.index,
        quality: domain.SleepQuality.unknown.index,
        isHealthKitImport: false,
        pluralkitUuid: null,
        pkImportSource: null,
        pkFileSwitchId: null,
        isDeleted: false,
      );

      final fields = fronting.toSyncFields(session);

      final startStr = fields['start_time'] as String;
      final endStr = fields['end_time'] as String;
      expect(
        startStr.endsWith('Z'),
        isTrue,
        reason: 'start_time must be UTC (Z-suffixed): got $startStr',
      );
      expect(
        endStr.endsWith('Z'),
        isTrue,
        reason: 'end_time must be UTC (Z-suffixed): got $endStr',
      );

      // The absolute instant must equal the input's UTC equivalent.
      expect(
        DateTime.parse(startStr).isAtSameMomentAs(localStart.toUtc()),
        isTrue,
      );
      expect(DateTime.parse(endStr).isAtSameMomentAs(localEnd.toUtc()), isTrue);
    },
  );

  test('members: created_at serializes as UTC (Z-suffixed)', () async {
    final db = database.AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final syncAdapter = buildSyncAdapterWithCompletion(db);
    final members = syncAdapter.adapter.entities.singleWhere(
      (e) => e.tableName == 'members',
    );

    // Local DateTime as the input — Drift hands these to toSyncFields.
    final localCreated = DateTime(2024, 1, 1, 12);
    final member = database.Member(
      id: 'm-utc-1',
      name: 'Ada',
      emoji: '✨',
      isActive: true,
      createdAt: localCreated,
      displayOrder: 0,
      isAdmin: false,
      customColorEnabled: false,
      profileHeaderSource: 1,
      profileHeaderLayout: 0,
      profileHeaderVisible: true,
      nameStyleFont: 0,
      nameStyleBold: true,
      nameStyleItalic: false,
      nameStyleColorMode: 0,
      pluralkitSyncIgnored: false,
      markdownEnabled: false,
      isDeleted: false,
      isAlwaysFronting: false,
    );

    final fields = members.toSyncFields(member);
    final createdStr = fields['created_at'] as String;
    expect(
      createdStr.endsWith('Z'),
      isTrue,
      reason: 'created_at must be UTC (Z-suffixed): got $createdStr',
    );
    expect(
      DateTime.parse(createdStr).isAtSameMomentAs(localCreated.toUtc()),
      isTrue,
    );
  });

  test(
    'fronting_sessions: nullable end_time stays null (not "null" string)',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final fronting = syncAdapter.adapter.entities.singleWhere(
        (e) => e.tableName == 'fronting_sessions',
      );

      final session = database.FrontingSession(
        id: 'fs-utc-2',
        startTime: DateTime(2024, 1, 1, 12),
        endTime: null,
        memberId: null,
        coFronterIds: '[]',
        sessionType: domain.SessionType.normal.index,
        quality: domain.SleepQuality.unknown.index,
        isHealthKitImport: false,
        pluralkitUuid: null,
        pkImportSource: null,
        pkFileSwitchId: null,
        isDeleted: false,
      );

      final fields = fronting.toSyncFields(session);
      expect(fields.containsKey('end_time'), isTrue);
      expect(fields['end_time'], isNull);
    },
  );

  // ---------------------------------------------------------------------------
  // Unknown sentinel: sync-apply hardDelete must refuse to remove the row.
  //
  // The repository-level deleteMember guard is bypassed by the sync apply
  // path (incoming tombstones flow through DriftSyncEntity.hardDelete, not
  // through the repository). An older or buggy peer emitting a delete op
  // for `unknownSentinelMemberId` must NOT be able to remove the local row,
  // because orphan-classified fronting sessions ("Front as Unknown" plus
  // importer/migration fallbacks) attribute back to it.
  // ---------------------------------------------------------------------------

  test(
    'members.hardDelete refuses remote delete of the Unknown sentinel',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final members = syncAdapter.adapter.entities.singleWhere(
        (entity) => entity.tableName == 'members',
      );

      // Seed the sentinel row directly so we can prove a hardDelete leaves
      // it in place.
      await db
          .into(db.members)
          .insert(
            database.MembersCompanion.insert(
              id: unknownSentinelMemberId,
              name: 'Unknown',
              createdAt: DateTime.utc(2026, 1, 1),
            ),
          );

      // Sanity: row exists before the delete.
      final beforeRow = await (db.select(
        db.members,
      )..where((t) => t.id.equals(unknownSentinelMemberId))).getSingleOrNull();
      expect(beforeRow, isNotNull);

      // Apply the incoming hard-delete op via the sync entity. Must not throw
      // (throwing would break the sync loop) and must leave the row intact.
      await members.hardDelete(unknownSentinelMemberId);

      final afterRow = await (db.select(
        db.members,
      )..where((t) => t.id.equals(unknownSentinelMemberId))).getSingleOrNull();
      expect(
        afterRow,
        isNotNull,
        reason: 'Unknown sentinel must survive a remote hardDelete',
      );
      expect(afterRow!.id, unknownSentinelMemberId);
    },
  );

  test('members.hardDelete still removes ordinary member rows', () async {
    final db = database.AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final syncAdapter = buildSyncAdapterWithCompletion(db);
    final members = syncAdapter.adapter.entities.singleWhere(
      (entity) => entity.tableName == 'members',
    );

    const ordinaryId = 'ordinary-member-1';
    await db
        .into(db.members)
        .insert(
          database.MembersCompanion.insert(
            id: ordinaryId,
            name: 'Ada',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );

    await members.hardDelete(ordinaryId);

    final afterRow = await (db.select(
      db.members,
    )..where((t) => t.id.equals(ordinaryId))).getSingleOrNull();
    expect(
      afterRow,
      isNull,
      reason: 'sentinel guard must not affect non-sentinel ids',
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // WS1 step 4 + 5 (PR B): the apply path for fronting_sessions and
  // front_session_comments must defer remote payloads via the quarantine
  // channel (rather than silently skip) when the per-member fronting
  // migration is `blocked` or `inProgress`.
  // ──────────────────────────────────────────────────────────────────────────

  test('fronting_sessions applyFields defers via quarantine while migration is '
      'blocked', () async {
    final db = database.AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final quarantine = SyncQuarantineService(db.syncQuarantineDao);
    final syncAdapter = buildSyncAdapterWithCompletion(
      db,
      quarantine: quarantine,
      applyGate: (table) {
        if (table == 'fronting_sessions') {
          return DriftSyncApplyRefusal.frontingMigrationGate;
        }
        return null;
      },
    );

    final sessions = syncAdapter.adapter.entities.singleWhere(
      (entity) => entity.tableName == 'fronting_sessions',
    );

    syncAdapter.beginSyncBatch();
    await sessions.applyFields('session-blocked', {
      'start_time': DateTime.utc(2026, 4, 29, 10).toIso8601String(),
      'session_type': 0,
      'is_health_kit_import': false,
      'is_deleted': false,
    });
    await syncAdapter.completeSyncBatch();

    // No fronting_sessions row should have been written.
    final row = await (db.select(
      db.frontingSessions,
    )..where((t) => t.id.equals('session-blocked'))).getSingleOrNull();
    expect(row, isNull, reason: 'gate must hold the apply back from disk');

    // Quarantine must have logged the deferred apply with a typed reason.
    final entries = await db.syncQuarantineDao.getAll();
    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.entityType, 'fronting_sessions');
    expect(entry.entityId, 'session-blocked');
    expect(entry.expectedType, 'apply');
    expect(entry.receivedType, 'deferred');
    expect(
      entry.errorMessage,
      contains('frontingMigrationGate'),
      reason:
          'errorMessage must name the refusal reason so diagnostics can '
          'trace deferred rows back to the migration gate',
    );
  });

  test(
    'front_session_comments applyFields defers via quarantine while migration '
    'is blocked',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final quarantine = SyncQuarantineService(db.syncQuarantineDao);
      final syncAdapter = buildSyncAdapterWithCompletion(
        db,
        quarantine: quarantine,
        applyGate: (table) {
          if (table == 'front_session_comments') {
            return DriftSyncApplyRefusal.frontingMigrationGate;
          }
          return null;
        },
      );

      final comments = syncAdapter.adapter.entities.singleWhere(
        (entity) => entity.tableName == 'front_session_comments',
      );

      syncAdapter.beginSyncBatch();
      await comments.applyFields('comment-blocked', {
        'session_id': 'session-1',
        'body': 'queued comment',
        'timestamp': DateTime.utc(2026, 4, 29, 12, 1).toIso8601String(),
        'created_at': DateTime.utc(2026, 4, 29, 12, 2).toIso8601String(),
        'is_deleted': false,
      });
      await syncAdapter.completeSyncBatch();

      final row = await (db.select(
        db.frontSessionComments,
      )..where((t) => t.id.equals('comment-blocked'))).getSingleOrNull();
      expect(row, isNull);

      final entries = await db.syncQuarantineDao.getAll();
      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.entityType, 'front_session_comments');
      expect(entry.entityId, 'comment-blocked');
      expect(entry.receivedType, 'deferred');
    },
  );

  test('fronting_sessions soft tombstone bypasses migration gate', () async {
    final db = database.AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.frontingSessions)
        .insert(
          database.FrontingSessionsCompanion.insert(
            id: 'session-delete',
            startTime: DateTime.utc(2026, 4, 29, 10),
            memberId: const Value('member-1'),
            isDeleted: const Value(false),
          ),
        );

    final quarantine = SyncQuarantineService(db.syncQuarantineDao);
    final syncAdapter = buildSyncAdapterWithCompletion(
      db,
      quarantine: quarantine,
      applyGate: (table) => table == 'fronting_sessions'
          ? DriftSyncApplyRefusal.frontingMigrationGate
          : null,
    );
    final sessions = syncAdapter.adapter.entities.singleWhere(
      (entity) => entity.tableName == 'fronting_sessions',
    );

    await sessions.applyFields('session-delete', {'is_deleted': true});

    final row = await (db.select(
      db.frontingSessions,
    )..where((t) => t.id.equals('session-delete'))).getSingle();
    expect(row.isDeleted, isTrue);
    expect(await db.syncQuarantineDao.count(), 0);
  });

  test(
    'front_session_comments soft tombstone bypasses migration gate',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.frontSessionComments)
          .insert(
            database.FrontSessionCommentsCompanion.insert(
              id: 'comment-delete',
              sessionId: 'session-delete',
              body: 'queued comment',
              timestamp: DateTime.utc(2026, 4, 29, 12, 1),
              createdAt: DateTime.utc(2026, 4, 29, 12, 2),
              isDeleted: const Value(false),
            ),
          );

      final quarantine = SyncQuarantineService(db.syncQuarantineDao);
      final syncAdapter = buildSyncAdapterWithCompletion(
        db,
        quarantine: quarantine,
        applyGate: (table) => table == 'front_session_comments'
            ? DriftSyncApplyRefusal.frontingMigrationGate
            : null,
      );
      final comments = syncAdapter.adapter.entities.singleWhere(
        (entity) => entity.tableName == 'front_session_comments',
      );

      await comments.applyFields('comment-delete', {'is_deleted': true});

      final row = await (db.select(
        db.frontSessionComments,
      )..where((t) => t.id.equals('comment-delete'))).getSingle();
      expect(row.isDeleted, isTrue);
      expect(await db.syncQuarantineDao.count(), 0);
    },
  );

  test('fronting_sessions apply succeeds when the gate clears (no quarantine '
      'entry)', () async {
    // Control: with no gate refusal, the existing apply path runs and no
    // deferred-quarantine entry is created. Pins that the gate is the
    // only writer to that channel.
    final db = database.AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final quarantine = SyncQuarantineService(db.syncQuarantineDao);
    final syncAdapter = buildSyncAdapterWithCompletion(
      db,
      quarantine: quarantine,
      applyGate: (_) => null,
    );

    final sessions = syncAdapter.adapter.entities.singleWhere(
      (entity) => entity.tableName == 'fronting_sessions',
    );

    syncAdapter.beginSyncBatch();
    await sessions.applyFields('session-clear', {
      'start_time': DateTime.utc(2026, 4, 29, 10).toIso8601String(),
      'session_type': 0,
      'member_id': 'm1',
      'is_health_kit_import': false,
      'is_deleted': false,
    });
    await syncAdapter.completeSyncBatch();

    final row = await (db.select(
      db.frontingSessions,
    )..where((t) => t.id.equals('session-clear'))).getSingleOrNull();
    expect(row, isNotNull);
    expect(await db.syncQuarantineDao.count(), 0);
  });
}

void _recordFullRemotePayloadReadBackFailures({
  required Map<String, Object> failures,
  required String table,
  required Map<String, dynamic>? row,
  required Map<String, dynamic> fields,
  required String nullRowMessage,
}) {
  if (row == null) {
    failures[table] = nullRowMessage;
    return;
  }

  final expected = _expectedReadRowForRemotePayload(table, fields);
  final expectedKeys = expected.keys.toSet();
  final actualKeys = row.keys.toSet();
  final missingKeys = expectedKeys.difference(actualKeys);
  final unexpectedKeys = actualKeys.difference(expectedKeys);
  if (missingKeys.isNotEmpty || unexpectedKeys.isNotEmpty) {
    failures['$table.<field-set>'] =
        'missing ${missingKeys.toList()}, unexpected ${unexpectedKeys.toList()}';
  }

  for (final entry in expected.entries) {
    if (row[entry.key] != entry.value) {
      failures['$table.${entry.key}'] =
          'expected ${entry.value}, got ${row[entry.key]}';
    }
  }
}

Map<String, dynamic> _expectedReadRowForRemotePayload(
  String table,
  Map<String, dynamic> fields,
) {
  final expected = Map<String, dynamic>.from(fields);
  if (table == 'member_group_entries') {
    // PK-backed entry sync treats sender-local group/member ids as hints and
    // persists the receiver's local row ids after resolving the stable PK UUIDs.
    expected['group_id'] = 'pk-group:pk-group-uuid';
    expected['member_id'] = 'member-1';
  }
  if (table == 'members' && expected['age'] is num) {
    // `age` migrated Int → String (schema v31). An old-client payload sends a
    // bare Int; the age decode site coerces it to its string form, so the
    // read-back value is the String, not the raw wire Int.
    expected['age'] = expected['age'].toString();
  }
  return expected;
}
