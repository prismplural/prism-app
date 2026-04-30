import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
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

void main() {
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
    'front_session_comments applyFields writes legacy session_id sentinel',
    () async {
      final db = database.AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final syncAdapter = buildSyncAdapterWithCompletion(db);
      final comments = syncAdapter.adapter.entities.singleWhere(
        (entity) => entity.tableName == 'front_session_comments',
      );

      await comments.applyFields('comment-1', {
        'target_time': DateTime.utc(2026, 4, 29, 12).toIso8601String(),
        'author_member_id': 'member-1',
        'body': 'hello',
        'timestamp': DateTime.utc(2026, 4, 29, 12, 1).toIso8601String(),
        'created_at': DateTime.utc(2026, 4, 29, 12, 2).toIso8601String(),
        'is_deleted': false,
      });

      final row = await (db.select(
        db.frontSessionComments,
      )..where((t) => t.id.equals('comment-1'))).getSingle();
      expect(row.sessionId, '');
      expect(row.targetTime?.toUtc(), DateTime.utc(2026, 4, 29, 12));
      expect(row.authorMemberId, 'member-1');
      expect(row.body, 'hello');
    },
  );

  test(
    'sync applyFields can create every entity from a remote payload',
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
        final fields = Map<String, dynamic>.from(_remoteCreatePayloads[table]!);
        try {
          await entity.applyFields(id, fields);
          final row = await entity.readRow(id);
          if (row == null) {
            failures[table] = 'applyFields completed but readRow returned null';
          } else {
            final expected = _expectedReadRowForRemotePayload(table, fields);
            for (final entry in expected.entries) {
              if (row[entry.key] != entry.value) {
                failures['$table.${entry.key}'] =
                    'expected ${entry.value}, got ${row[entry.key]}';
              }
            }
          }
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
        isActive: true,
        createdAt: DateTime.utc(2026, 3, 18),
        displayOrder: 1,
        isAdmin: false,
        customColorEnabled: false,
        pluralkitUuid: 'uuid-ada',
        pluralkitId: 'ada',
        displayName: 'Ada Lovelace',
        birthday: '1815-12-10',
        proxyTagsJson: '[{"prefix":"A:","suffix":null}]',
        pkBannerUrl: 'https://example.invalid/banner.png',
        profileHeaderSource: 0,
        profileHeaderLayout: 1,
        profileHeaderVisible: false,
        profileHeaderImageData: Uint8List.fromList([4, 5, 6]),
        pkBannerImageData: Uint8List.fromList([7, 8, 9]),
        pkBannerCachedUrl: 'https://example.invalid/banner.png',
        pluralkitSyncIgnored: true,
        markdownEnabled: true,
        isDeleted: false,
        isAlwaysFronting: false,
      );

      final back = await roundTripMember(db, member);
      expect(back['display_name'], 'Ada Lovelace');
      expect(back['birthday'], '1815-12-10');
      expect(back['proxy_tags_json'], '[{"prefix":"A:","suffix":null}]');
      expect(back['pluralkit_sync_ignored'], isTrue);
      expect(back['pluralkit_id'], 'ada');
      expect(back['pluralkit_uuid'], 'uuid-ada');
      expect(back['pk_banner_url'], 'https://example.invalid/banner.png');
      expect(back['profile_header_source'], 0);
      expect(back['profile_header_layout'], 1);
      expect(back['profile_header_visible'], isFalse);
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
      expect(back.containsKey('pk_banner_url'), isTrue);
      expect(back['profile_header_visible'], isTrue);
      expect(back['pk_banner_url'], isNull);
      expect(back['profile_header_source'], 1);
      expect(back['profile_header_layout'], 0);
      expect(back.containsKey('profile_header_image_data'), isTrue);
      expect(back['profile_header_image_data'], isNull);
      expect(back.containsKey('pk_banner_image_data'), isTrue);
      expect(back['pk_banner_image_data'], isNull);
      expect(back.containsKey('pk_banner_cached_url'), isTrue);
      expect(back['pk_banner_cached_url'], isNull);
      expect(back['pluralkit_sync_ignored'], isFalse);
      expect(back['pluralkit_uuid'], isNull);
      expect(back['pluralkit_id'], isNull);
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
  return expected;
}

const _remoteIso = '2026-04-29T12:00:00.000Z';
const _remoteIsoLater = '2026-04-29T12:05:00.000Z';

const _remoteCreateOrder = <String>[
  'members',
  'fronting_sessions',
  'conversations',
  'chat_messages',
  'system_settings',
  'polls',
  'poll_options',
  'poll_votes',
  'habits',
  'habit_completions',
  'conversation_categories',
  'reminders',
  'member_groups',
  'member_group_entries',
  'custom_fields',
  'custom_field_values',
  'notes',
  'front_session_comments',
  'friends',
  'media_attachments',
];

const _remoteCreateIds = <String, String>{
  'members': 'member-1',
  'fronting_sessions': 'front-1',
  'conversations': 'conversation-1',
  'chat_messages': 'message-1',
  'system_settings': 'singleton',
  'polls': 'poll-1',
  'poll_options': 'poll-option-1',
  'poll_votes': 'poll-vote-1',
  'habits': 'habit-1',
  'habit_completions': 'habit-completion-1',
  'conversation_categories': 'conversation-category-1',
  'reminders': 'reminder-1',
  'member_groups': 'pk-group:pk-group-uuid',
  'member_group_entries': 'member-group-entry-1',
  'custom_fields': 'custom-field-1',
  'custom_field_values': 'custom-field-value-1',
  'notes': 'note-1',
  'front_session_comments': 'front-comment-1',
  'friends': 'friend-1',
  'media_attachments': 'media-attachment-1',
};

const _remoteCreatePayloads = <String, Map<String, dynamic>>{
  'members': {
    'name': 'Ada',
    'pronouns': 'they/them',
    'emoji': '*',
    'age': 33,
    'bio': 'bio',
    'avatar_image_data': 'AQID',
    'is_active': true,
    'created_at': _remoteIso,
    'display_order': 1,
    'is_admin': false,
    'custom_color_enabled': true,
    'custom_color_hex': '#112233',
    'parent_system_id': 'system-1',
    'pluralkit_uuid': 'pk-member-uuid',
    'pluralkit_id': 'abcde',
    'markdown_enabled': true,
    'display_name': 'Ada Display',
    'birthday': '2000-01-01',
    'proxy_tags_json': '[]',
    'pk_banner_url': 'https://example.invalid/banner.png',
    'profile_header_source': 0,
    'profile_header_layout': 1,
    'profile_header_image_data': 'BAUG',
    'pk_banner_image_data': 'BwgJ',
    'pk_banner_cached_url': 'https://example.invalid/banner.png',
    'pluralkit_sync_ignored': false,
    'delete_push_started_at': 0,
    'is_always_fronting': false,
    'is_deleted': false,
  },
  'fronting_sessions': {
    'start_time': _remoteIso,
    'end_time': _remoteIsoLater,
    'member_id': 'member-1',
    'notes': 'notes',
    'confidence': 1,
    'session_type': 0,
    'quality': 1,
    'is_health_kit_import': false,
    'pluralkit_uuid': 'pk-switch-uuid',
    'pk_import_source': 'file',
    'pk_file_switch_id': 'remote-switch-1',
    'delete_push_started_at': 0,
    'is_deleted': false,
  },
  'conversations': {
    'created_at': _remoteIso,
    'last_activity_at': _remoteIsoLater,
    'title': 'Conversation',
    'emoji': '*',
    'is_direct_message': false,
    'creator_id': 'member-1',
    'participant_ids': '["member-1"]',
    'archived_by_member_ids': '[]',
    'muted_by_member_ids': '["member-1"]',
    'last_read_timestamps': '{}',
    'description': 'description',
    'category_id': 'conversation-category-1',
    'display_order': 1,
    'is_deleted': false,
  },
  'chat_messages': {
    'content': 'hello',
    'timestamp': _remoteIso,
    'is_system_message': false,
    'edited_at': _remoteIsoLater,
    'author_id': 'member-1',
    'conversation_id': 'conversation-1',
    'reactions': '[]',
    'reply_to_id': 'reply-1',
    'reply_to_author_id': 'member-1',
    'reply_to_content': 'reply',
    'is_deleted': false,
  },
  'system_settings': {
    'system_name': 'System',
    'sharing_id': 'share-1',
    'show_quick_front': true,
    'accent_color_hex': '#112233',
    'per_member_accent_colors': true,
    'terminology': 0,
    'custom_terminology': 'headmate',
    'custom_plural_terminology': 'system',
    'terminology_use_english': false,
    'fronting_reminders_enabled': true,
    'fronting_reminder_interval_minutes': 60,
    'theme_mode': 0,
    'theme_brightness': 0,
    'theme_style': 0,
    'theme_corner_style': 0,
    'chat_enabled': true,
    'gif_search_enabled': true,
    'voice_notes_enabled': true,
    'locale_override': 'en',
    'polls_enabled': true,
    'habits_enabled': true,
    'sleep_tracking_enabled': true,
    'quick_switch_threshold_seconds': 30,
    'identity_generation': 1,
    'sleep_suggestion_enabled': true,
    'sleep_suggestion_hour': 22,
    'sleep_suggestion_minute': 0,
    'wake_suggestion_enabled': true,
    'wake_suggestion_after_hours': 8.0,
    'chat_logs_front': false,
    'sync_theme_enabled': true,
    'timing_mode': 0,
    'notes_enabled': true,
    'pk_group_sync_v2_enabled': true,
    'system_color': '#445566',
    'system_description': 'description',
    'system_tag': 'tag',
    'system_avatar_data': 'AQID',
    'reminders_enabled': true,
    'sync_navigation_enabled': true,
    'habits_badge_enabled': true,
    'nav_bar_items': '["fronting"]',
    'nav_bar_overflow_items': '[]',
    'chat_badge_preferences': '{}',
    'fronting_list_view_mode': 0,
    'add_front_default_behavior': 0,
    'quick_front_default_behavior': 0,
    'is_deleted': false,
  },
  'polls': {
    'question': 'Question?',
    'description': 'description',
    'is_anonymous': false,
    'allows_multiple_votes': true,
    'is_closed': false,
    'expires_at': _remoteIsoLater,
    'created_at': _remoteIso,
    'is_deleted': false,
  },
  'poll_options': {
    'poll_id': 'poll-1',
    'option_text': 'Option',
    'sort_order': 1,
    'is_other_option': false,
    'color_hex': '#112233',
    'is_deleted': false,
  },
  'poll_votes': {
    'poll_option_id': 'poll-option-1',
    'member_id': 'member-1',
    'voted_at': _remoteIso,
    'response_text': 'response',
    'is_deleted': false,
  },
  'habits': {
    'name': 'Habit',
    'description': 'description',
    'icon': 'check',
    'color_hex': '#112233',
    'is_active': true,
    'created_at': _remoteIso,
    'modified_at': _remoteIsoLater,
    'frequency': 'daily',
    'weekly_days': '[1,2]',
    'interval_days': 1,
    'reminder_time': '08:00',
    'notifications_enabled': true,
    'notification_message': 'do it',
    'assigned_member_id': 'member-1',
    'only_notify_when_fronting': false,
    'is_private': false,
    'current_streak': 1,
    'best_streak': 2,
    'total_completions': 3,
    'is_deleted': false,
  },
  'habit_completions': {
    'habit_id': 'habit-1',
    'completed_at': _remoteIso,
    'completed_by_member_id': 'member-1',
    'notes': 'notes',
    'was_fronting': true,
    'rating': 5,
    'created_at': _remoteIso,
    'modified_at': _remoteIsoLater,
    'is_deleted': false,
  },
  'conversation_categories': {
    'name': 'Category',
    'display_order': 1,
    'created_at': _remoteIso,
    'modified_at': _remoteIsoLater,
    'is_deleted': false,
  },
  'reminders': {
    'name': 'Reminder',
    'message': 'message',
    'trigger': 0,
    'interval_days': 1,
    'time_of_day': '09:00',
    'delay_hours': 1,
    'target_member_id': 'member-1',
    'is_active': true,
    'created_at': _remoteIso,
    'modified_at': _remoteIsoLater,
    'frequency': 'daily',
    'weekly_days': '[1,2]',
    'is_deleted': false,
  },
  'member_groups': {
    'name': 'Group',
    'description': 'description',
    'color_hex': '#112233',
    'emoji': '*',
    'display_order': 1,
    'parent_group_id': 'parent-group',
    'group_type': 0,
    'filter_rules': '{}',
    'created_at': _remoteIso,
    'pluralkit_id': 'abcde',
    'pluralkit_uuid': 'pk-group-uuid',
    'last_seen_from_pk_at': _remoteIso,
    'is_deleted': false,
  },
  'member_group_entries': {
    'group_id': 'sender-local-group',
    'member_id': 'sender-local-member',
    'pk_group_uuid': 'pk-group-uuid',
    'pk_member_uuid': 'pk-member-uuid',
    'is_deleted': false,
  },
  'custom_fields': {
    'name': 'Field',
    'field_type': 0,
    'date_precision': 0,
    'display_order': 1,
    'created_at': _remoteIso,
    'is_deleted': false,
  },
  'custom_field_values': {
    'custom_field_id': 'custom-field-1',
    'member_id': 'member-1',
    'value': 'value',
    'is_deleted': false,
  },
  'notes': {
    'title': 'Note',
    'body': 'body',
    'color_hex': '#112233',
    'member_id': 'member-1',
    'date': _remoteIso,
    'created_at': _remoteIso,
    'modified_at': _remoteIsoLater,
    'is_deleted': false,
  },
  'front_session_comments': {
    'target_time': _remoteIso,
    'author_member_id': 'member-1',
    'body': 'comment',
    'timestamp': _remoteIso,
    'created_at': _remoteIsoLater,
    'is_deleted': false,
  },
  'friends': {
    'display_name': 'Friend',
    'peer_sharing_id': 'peer-1',
    'pairwise_secret': 'AQID',
    'pinned_identity': 'BAUG',
    'offered_scopes': '[]',
    'public_key_hex': 'deadbeef',
    'shared_secret_hex': 'secret',
    'granted_scopes': '[]',
    'is_verified': true,
    'init_id': 'init-1',
    'created_at': _remoteIso,
    'established_at': _remoteIso,
    'last_sync_at': _remoteIsoLater,
    'is_deleted': false,
  },
  'media_attachments': {
    'message_id': 'message-1',
    'media_id': 'media-1',
    'media_type': 'image',
    'encryption_key_b64': 'AQID',
    'content_hash': 'hash',
    'plaintext_hash': 'plain',
    'mime_type': 'image/png',
    'size_bytes': 12,
    'width': 10,
    'height': 10,
    'duration_ms': 0,
    'blurhash': 'blur',
    'waveform_b64': '',
    'thumbnail_media_id': '',
    'source_url': '',
    'preview_url': '',
    'is_deleted': false,
  },
};
