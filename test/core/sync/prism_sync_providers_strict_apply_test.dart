import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as database;
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart';
import 'package:prism_plurality/core/sync/sync_event_loop.dart';
import 'package:prism_sync_drift/prism_sync_drift.dart';

/// Fake entity that fails on a configurable set of entity ids. Used to
/// simulate per-row apply failures without needing the real Drift mapping
/// to be configured for every table under test.
DriftSyncEntity _fakeEntity({
  required String tableName,
  required bool Function(String entityId) shouldFail,
  required List<String> appliedIds,
}) {
  return DriftSyncEntity(
    tableName: tableName,
    toSyncFields: (_) => <String, dynamic>{},
    applyFields: (id, fields) async {
      if (shouldFail(id)) {
        throw StateError('applyFields failed for $tableName/$id');
      }
      appliedIds.add('$tableName/$id');
    },
    hardDelete: (id) async {
      appliedIds.add('delete $tableName/$id');
    },
    readRow: (_) async => null,
    isDeleted: (_) async => false,
  );
}

SyncEvent _eventFromChanges(List<Map<String, dynamic>> changes) {
  return SyncEvent.fromJson({'type': 'RemoteChanges', 'changes': changes});
}

Map<String, dynamic> _frontingFields({
  required String notes,
  required String pkUuid,
  String? memberId = 'member-1',
  int sessionType = 0,
  DateTime? startTime,
  bool isDeleted = false,
}) {
  final startedAt = startTime ?? DateTime.utc(2026, 6, 5, 12);
  return <String, dynamic>{
    'start_time': startedAt.toIso8601String(),
    'end_time': startedAt.add(const Duration(hours: 1)).toIso8601String(),
    'member_id': memberId,
    'notes': notes,
    'confidence': 1,
    'session_type': sessionType,
    'quality': null,
    'is_health_kit_import': false,
    'pluralkit_uuid': pkUuid,
    'pk_import_source': 'api',
    'pk_file_switch_id': 'switch-1',
    'delete_push_started_at': null,
    'is_deleted': isDeleted,
  };
}

void main() {
  late database.AppDatabase db;

  setUp(() {
    db = database.AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('applyRemoteChanges — non-strict mode', () {
    test('per-row failure is swallowed and subsequent rows apply', () async {
      final applied = <String>[];
      final adapter = DriftSyncAdapter(
        entities: [
          _fakeEntity(
            tableName: 'members',
            shouldFail: (id) => id == 'bad',
            appliedIds: applied,
          ),
        ],
      );

      final event = _eventFromChanges([
        {
          'table': 'members',
          'entity_id': 'ok-1',
          'is_delete': false,
          'fields': {'name': 'A'},
        },
        {
          'table': 'members',
          'entity_id': 'bad',
          'is_delete': false,
          'fields': {'name': 'B'},
        },
        {
          'table': 'members',
          'entity_id': 'ok-2',
          'is_delete': false,
          'fields': {'name': 'C'},
        },
      ]);

      final result = await applyRemoteChanges(db, adapter, event);
      expect(result.rowsApplied, 2);
      expect(result.failedTables, isEmpty);
      expect(applied, containsAll(['members/ok-1', 'members/ok-2']));
      expect(applied, isNot(contains('members/bad')));
    });
  });

  group('applyRemoteChanges — strict mode', () {
    test('first-row failure rethrows; subsequent rows not applied', () async {
      final applied = <String>[];
      final adapter = DriftSyncAdapter(
        entities: [
          _fakeEntity(
            tableName: 'members',
            shouldFail: (id) => id == 'bad',
            appliedIds: applied,
          ),
        ],
      );

      final event = _eventFromChanges([
        {
          'table': 'members',
          'entity_id': 'ok-1',
          'is_delete': false,
          'fields': {'name': 'A'},
        },
        {
          'table': 'members',
          'entity_id': 'bad',
          'is_delete': false,
          'fields': {'name': 'B'},
        },
        {
          'table': 'members',
          'entity_id': 'ok-2',
          'is_delete': false,
          'fields': {'name': 'C'},
        },
      ]);

      await expectLater(
        applyRemoteChanges(db, adapter, event, strict: true),
        throwsA(
          isA<StrictApplyFailure>()
              .having((e) => e.table, 'table', 'members')
              .having((e) => e.entityId, 'entityId', 'bad')
              .having((e) => e.failedTables, 'failedTables', ['members']),
        ),
      );

      expect(applied, contains('members/ok-1'));
      // The row after the failure must NOT have been applied — strict mode
      // aborts immediately.
      expect(applied, isNot(contains('members/ok-2')));
    });

    test('all rows succeeding returns success ApplyResult', () async {
      final applied = <String>[];
      final adapter = DriftSyncAdapter(
        entities: [
          _fakeEntity(
            tableName: 'members',
            shouldFail: (_) => false,
            appliedIds: applied,
          ),
        ],
      );

      final event = _eventFromChanges([
        {
          'table': 'members',
          'entity_id': 'a',
          'is_delete': false,
          'fields': <String, dynamic>{},
        },
        {
          'table': 'members',
          'entity_id': 'b',
          'is_delete': false,
          'fields': <String, dynamic>{},
        },
      ]);

      final result = await applyRemoteChanges(db, adapter, event, strict: true);
      expect(result.rowsApplied, 2);
      expect(result.failedTables, isEmpty);
      expect(applied, ['members/a', 'members/b']);
    });

    test('successful rows emit strict apply progress', () async {
      final applied = <String>[];
      final adapter = DriftSyncAdapter(
        entities: [
          _fakeEntity(
            tableName: 'members',
            shouldFail: (_) => false,
            appliedIds: applied,
          ),
        ],
      );

      final event = _eventFromChanges([
        {
          'table': 'members',
          'entity_id': 'a',
          'is_delete': false,
          'fields': <String, dynamic>{},
        },
        {
          'table': 'members',
          'entity_id': 'b',
          'is_delete': false,
          'fields': <String, dynamic>{},
        },
      ]);

      var progressTicks = 0;
      final result = await applyRemoteChanges(
        db,
        adapter,
        event,
        strict: true,
        onProgress: (applied, total) {
          progressTicks++;
          expect(total, 2);
          expect(applied, inInclusiveRange(1, 2));
        },
      );

      expect(result.rowsApplied, 2);
      expect(progressTicks, 2);
    });

    test('unknown tombstones do not abort strict pairing apply', () async {
      final adapter = buildSyncAdapterWithCompletion(db).adapter;
      final idsByTable = {
        'conversations': 'missing-conversation',
        'member_groups': 'pk-group:missing-pk-group',
        'member_group_entries': 'missing-member-group-entry',
        'chat_messages': 'missing-message',
        'system_settings': 'singleton',
      };
      final event = _eventFromChanges([
        for (final entity in adapter.entities)
          {
            'table': entity.tableName,
            'entity_id':
                idsByTable[entity.tableName] ?? 'missing-${entity.tableName}',
            'is_delete': false,
            'fields': {'is_deleted': true},
          },
      ]);

      final result = await applyRemoteChanges(db, adapter, event, strict: true);

      expect(result.rowsApplied, adapter.entities.length);
      final group = await adapter
          .entityForTable('member_groups')!
          .readRow('pk-group:missing-pk-group');
      expect(group, isNotNull);
      expect(group?['pluralkit_uuid'], 'missing-pk-group');
      expect(group?['is_deleted'], isTrue);

      final message = await (db.select(
        db.chatMessages,
      )..where((t) => t.id.equals('missing-message'))).getSingleOrNull();
      expect(message, isNull);
    });

    test(
      'sparse conversation visibility patch does not abort strict pairing apply',
      () async {
        final adapter = buildSyncAdapterWithCompletion(db).adapter;

        final result = await applyRemoteChanges(
          db,
          adapter,
          _eventFromChanges([
            {
              'table': 'conversations',
              'entity_id': 'conversation-1',
              'is_delete': false,
              'fields': {'includes_all_members': true},
            },
          ]),
          strict: true,
        );

        expect(result.rowsApplied, 1);
        final row = await (db.select(
          db.conversations,
        )..where((t) => t.id.equals('conversation-1'))).getSingle();
        expect(row.includesAllMembers, isTrue);
        expect(row.isDeleted, isFalse);
      },
    );

    test(
      'unknown sparse row patch does not abort strict pairing apply',
      () async {
        final adapter = buildSyncAdapterWithCompletion(db).adapter;

        final result = await applyRemoteChanges(
          db,
          adapter,
          _eventFromChanges([
            {
              'table': 'chat_messages',
              'entity_id': 'message-1',
              'is_delete': false,
              'fields': {
                'edited_at': DateTime.utc(2026, 6, 5, 12).toIso8601String(),
              },
            },
          ]),
          strict: true,
        );

        expect(result.rowsApplied, 1);
        final row = await (db.select(
          db.chatMessages,
        )..where((t) => t.id.equals('message-1'))).getSingleOrNull();
        expect(row, isNull);
      },
    );

    test(
      'duplicate PK-backed group-entry records do not abort strict pairing apply',
      () async {
        final adapter = buildSyncAdapterWithCompletion(db).adapter;
        final now = DateTime.utc(2026, 6, 5, 12);

        await db
            .into(db.memberGroups)
            .insert(
              database.MemberGroupsCompanion.insert(
                id: 'pk-group:pk-group-1',
                name: 'PK Group',
                createdAt: now,
                pluralkitUuid: const drift.Value('pk-group-1'),
              ),
            );
        await db
            .into(db.members)
            .insert(
              database.MembersCompanion.insert(
                id: 'member-1',
                name: 'Member',
                createdAt: now,
                pluralkitUuid: const drift.Value('pk-member-1'),
              ),
            );

        final canonicalEntryId = sha256
            .convert(utf8.encode('pk-group-1\u0000pk-member-1'))
            .toString()
            .substring(0, 16);
        final fields = <String, dynamic>{
          'group_id': 'sender-local-group',
          'member_id': 'member-1',
          'pk_group_uuid': 'pk-group-1',
          'pk_member_uuid': 'pk-member-1',
          'is_deleted': false,
        };
        final event = _eventFromChanges([
          {
            'table': 'member_group_entries',
            'entity_id': 'legacy-entry-id',
            'is_delete': false,
            'fields': fields,
          },
          {
            'table': 'member_group_entries',
            'entity_id': canonicalEntryId,
            'is_delete': false,
            'fields': fields,
          },
        ]);

        final result = await applyRemoteChanges(
          db,
          adapter,
          event,
          strict: true,
        );

        expect(result.rowsApplied, 2);
        final rows = await db.select(db.memberGroupEntries).get();
        final activeRows = rows.where((row) => !row.isDeleted).toList();
        expect(activeRows, hasLength(1));
        expect(activeRows.single.id, canonicalEntryId);
        expect(activeRows.single.groupId, 'pk-group:pk-group-1');
        expect(activeRows.single.memberId, 'member-1');
        expect(
          rows.singleWhere((row) => row.id == 'legacy-entry-id').isDeleted,
          isTrue,
        );
      },
    );

    test(
      'canonical PK-backed group-entry remains canonical after legacy duplicate',
      () async {
        final adapter = buildSyncAdapterWithCompletion(db).adapter;
        final now = DateTime.utc(2026, 6, 5, 12);

        await db
            .into(db.memberGroups)
            .insert(
              database.MemberGroupsCompanion.insert(
                id: 'pk-group:pk-group-1',
                name: 'PK Group',
                createdAt: now,
                pluralkitUuid: const drift.Value('pk-group-1'),
              ),
            );
        await db
            .into(db.members)
            .insert(
              database.MembersCompanion.insert(
                id: 'member-1',
                name: 'Member',
                createdAt: now,
                pluralkitUuid: const drift.Value('pk-member-1'),
              ),
            );

        final canonicalEntryId = sha256
            .convert(utf8.encode('pk-group-1\u0000pk-member-1'))
            .toString()
            .substring(0, 16);
        final fields = <String, dynamic>{
          'group_id': 'sender-local-group',
          'member_id': 'member-1',
          'pk_group_uuid': 'pk-group-1',
          'pk_member_uuid': 'pk-member-1',
          'is_deleted': false,
        };
        final result = await applyRemoteChanges(
          db,
          adapter,
          _eventFromChanges([
            {
              'table': 'member_group_entries',
              'entity_id': canonicalEntryId,
              'is_delete': false,
              'fields': fields,
            },
            {
              'table': 'member_group_entries',
              'entity_id': 'legacy-entry-id',
              'is_delete': false,
              'fields': fields,
            },
          ]),
          strict: true,
        );

        expect(result.rowsApplied, 2);
        final rows = await db.select(db.memberGroupEntries).get();
        expect(rows, hasLength(1));
        expect(rows.single.id, canonicalEntryId);
        expect(rows.single.groupId, 'pk-group:pk-group-1');
        expect(rows.single.memberId, 'member-1');
        expect(rows.single.isDeleted, isFalse);
      },
    );

    test(
      'duplicate PK-backed fronting-session records do not abort strict pairing apply',
      () async {
        final adapter = buildSyncAdapterWithCompletion(db).adapter;
        final fields = <String, dynamic>{
          'start_time': DateTime.utc(2026, 6, 5, 12).toIso8601String(),
          'end_time': DateTime.utc(2026, 6, 5, 13).toIso8601String(),
          'member_id': 'member-1',
          'notes': 'initial',
          'confidence': 1,
          'session_type': 0,
          'quality': null,
          'is_health_kit_import': false,
          'pluralkit_uuid': 'pk-switch-1',
          'pk_import_source': 'api',
          'pk_file_switch_id': 'switch-1',
          'delete_push_started_at': null,
          'is_deleted': false,
        };

        await applyRemoteChanges(
          db,
          adapter,
          _eventFromChanges([
            {
              'table': 'fronting_sessions',
              'entity_id': 'front-existing',
              'is_delete': false,
              'fields': fields,
            },
          ]),
          strict: true,
        );

        final result = await applyRemoteChanges(
          db,
          adapter,
          _eventFromChanges([
            {
              'table': 'fronting_sessions',
              'entity_id': 'front-incoming',
              'is_delete': false,
              'fields': {...fields, 'notes': 'incoming'},
            },
          ]),
          strict: true,
        );

        expect(result.rowsApplied, 1);
        final rows = await db.select(db.frontingSessions).get();
        expect(rows, hasLength(1));
        expect(rows.single.id, 'front-existing');
        expect(rows.single.notes, 'incoming');
        expect(rows.single.pluralkitUuid, 'pk-switch-1');
        expect(rows.single.memberId, 'member-1');
      },
    );

    test(
      'orphan PK-backed fronting-session records do not abort strict pairing apply',
      () async {
        final adapter = buildSyncAdapterWithCompletion(db).adapter;

        await applyRemoteChanges(
          db,
          adapter,
          _eventFromChanges([
            {
              'table': 'fronting_sessions',
              'entity_id': 'front-orphan-existing',
              'is_delete': false,
              'fields': _frontingFields(
                notes: 'initial',
                pkUuid: 'pk-orphan-switch-1',
                memberId: null,
                sessionType: 1,
              ),
            },
          ]),
          strict: true,
        );

        final result = await applyRemoteChanges(
          db,
          adapter,
          _eventFromChanges([
            {
              'table': 'fronting_sessions',
              'entity_id': 'front-orphan-incoming',
              'is_delete': false,
              'fields': _frontingFields(
                notes: 'incoming',
                pkUuid: 'pk-orphan-switch-1',
                memberId: null,
                sessionType: 1,
              ),
            },
          ]),
          strict: true,
        );

        expect(result.rowsApplied, 1);
        final rows = await db.select(db.frontingSessions).get();
        expect(rows, hasLength(1));
        expect(rows.single.id, 'front-orphan-existing');
        expect(rows.single.notes, 'incoming');
        expect(rows.single.pluralkitUuid, 'pk-orphan-switch-1');
        expect(rows.single.memberId, isNull);
        expect(rows.single.sessionType, 1);
      },
    );

    test(
      'deleted PK-backed fronting-session holder does not block active restore',
      () async {
        final adapter = buildSyncAdapterWithCompletion(db).adapter;
        final now = DateTime.utc(2026, 6, 5, 12);
        await db
            .into(db.frontingSessions)
            .insert(
              database.FrontingSessionsCompanion.insert(
                id: 'deleted-front-holder',
                startTime: now,
                memberId: const drift.Value('member-1'),
                pluralkitUuid: const drift.Value('pk-switch-1'),
                isDeleted: const drift.Value(true),
              ),
            );

        final result = await applyRemoteChanges(
          db,
          adapter,
          _eventFromChanges([
            {
              'table': 'fronting_sessions',
              'entity_id': 'front-active',
              'is_delete': false,
              'fields': {
                'start_time': now.toIso8601String(),
                'end_time': DateTime.utc(2026, 6, 5, 13).toIso8601String(),
                'member_id': 'member-1',
                'notes': 'active',
                'confidence': null,
                'session_type': 0,
                'quality': null,
                'is_health_kit_import': false,
                'pluralkit_uuid': 'pk-switch-1',
                'pk_import_source': 'api',
                'pk_file_switch_id': 'switch-1',
                'delete_push_started_at': null,
                'is_deleted': false,
              },
            },
          ]),
          strict: true,
        );

        expect(result.rowsApplied, 1);
        final rows = await db.select(db.frontingSessions).get();
        final deleted = rows.singleWhere(
          (row) => row.id == 'deleted-front-holder',
        );
        final active = rows.singleWhere((row) => row.id == 'front-active');
        expect(deleted.isDeleted, isTrue);
        expect(deleted.pluralkitUuid, isNull);
        expect(active.isDeleted, isFalse);
        expect(active.pluralkitUuid, 'pk-switch-1');
        expect(active.memberId, 'member-1');
      },
    );

    test(
      'deleted orphan PK-backed fronting-session holder does not block active restore',
      () async {
        final adapter = buildSyncAdapterWithCompletion(db).adapter;
        final now = DateTime.utc(2026, 6, 5, 12);
        await db
            .into(db.frontingSessions)
            .insert(
              database.FrontingSessionsCompanion.insert(
                id: 'deleted-front-orphan-holder',
                startTime: now,
                memberId: const drift.Value(null),
                sessionType: const drift.Value(1),
                pluralkitUuid: const drift.Value('pk-orphan-switch-1'),
                isDeleted: const drift.Value(true),
              ),
            );

        final result = await applyRemoteChanges(
          db,
          adapter,
          _eventFromChanges([
            {
              'table': 'fronting_sessions',
              'entity_id': 'front-orphan-active',
              'is_delete': false,
              'fields': _frontingFields(
                notes: 'active',
                pkUuid: 'pk-orphan-switch-1',
                memberId: null,
                sessionType: 1,
                startTime: now,
              ),
            },
          ]),
          strict: true,
        );

        expect(result.rowsApplied, 1);
        final rows = await db.select(db.frontingSessions).get();
        final deleted = rows.singleWhere(
          (row) => row.id == 'deleted-front-orphan-holder',
        );
        final active = rows.singleWhere(
          (row) => row.id == 'front-orphan-active',
        );
        expect(deleted.isDeleted, isTrue);
        expect(deleted.pluralkitUuid, isNull);
        expect(deleted.memberId, isNull);
        expect(active.isDeleted, isFalse);
        expect(active.pluralkitUuid, 'pk-orphan-switch-1');
        expect(active.memberId, isNull);
        expect(active.sessionType, 1);
      },
    );

    test(
      'duplicate member profile preference records do not abort strict pairing apply',
      () async {
        final adapter = buildSyncAdapterWithCompletion(db).adapter;
        final fields = <String, dynamic>{
          'member_id': 'member-1',
          'key': 'profile.header.visible',
          'value_type': 'bool',
          'value_json': 'true',
          'is_deleted': false,
        };

        await applyRemoteChanges(
          db,
          adapter,
          _eventFromChanges([
            {
              'table': 'member_profile_preference_values',
              'entity_id': 'legacy-pref-id',
              'is_delete': false,
              'fields': fields,
            },
          ]),
          strict: true,
        );

        final result = await applyRemoteChanges(
          db,
          adapter,
          _eventFromChanges([
            {
              'table': 'member_profile_preference_values',
              'entity_id': 'bWVtYmVyLTE:profile.header.visible',
              'is_delete': false,
              'fields': {...fields, 'value_json': 'false'},
            },
          ]),
          strict: true,
        );

        expect(result.rowsApplied, 1);
        final rows = await db.select(db.memberProfilePreferenceValues).get();
        expect(rows, hasLength(1));
        expect(rows.single.id, 'bWVtYmVyLTE:profile.header.visible');
        expect(rows.single.memberId, 'member-1');
        expect(rows.single.key, 'profile.header.visible');
        expect(rows.single.valueJson, 'false');
      },
    );

    test(
      'deleted member profile preference holder does not block active restore',
      () async {
        final adapter = buildSyncAdapterWithCompletion(db).adapter;
        final fields = <String, dynamic>{
          'member_id': 'member-1',
          'key': 'profile.header.visible',
          'value_type': 'bool',
          'value_json': null,
          'is_deleted': true,
        };

        await applyRemoteChanges(
          db,
          adapter,
          _eventFromChanges([
            {
              'table': 'member_profile_preference_values',
              'entity_id': 'legacy-pref-id',
              'is_delete': false,
              'fields': fields,
            },
          ]),
          strict: true,
        );

        final result = await applyRemoteChanges(
          db,
          adapter,
          _eventFromChanges([
            {
              'table': 'member_profile_preference_values',
              'entity_id': 'bWVtYmVyLTE:profile.header.visible',
              'is_delete': false,
              'fields': {...fields, 'value_json': 'true', 'is_deleted': false},
            },
          ]),
          strict: true,
        );

        expect(result.rowsApplied, 1);
        final rows = await db.select(db.memberProfilePreferenceValues).get();
        expect(rows, hasLength(1));
        expect(rows.single.id, 'bWVtYmVyLTE:profile.header.visible');
        expect(rows.single.memberId, 'member-1');
        expect(rows.single.key, 'profile.header.visible');
        expect(rows.single.valueJson, 'true');
        expect(rows.single.isDeleted, isFalse);
      },
    );
  });

  group('StrictApplyCoordinator', () {
    test('enter/exit toggles isStrict', () {
      final c = StrictApplyCoordinator();
      expect(c.isStrict, isFalse);
      c.enterStrictMode();
      expect(c.isStrict, isTrue);
      c.exitStrictMode();
      expect(c.isStrict, isFalse);
    });

    test('signalFailure resolves outcome with ApplyOutcomeFailure', () async {
      final c = StrictApplyCoordinator();
      final future = c.enterStrictMode();
      c.signalFailure(const StrictApplyFailure(message: 'boom'));
      final outcome = await future;
      expect(outcome, isA<ApplyOutcomeFailure>());
      expect((outcome as ApplyOutcomeFailure).failure.message, 'boom');
      c.exitStrictMode();
    });

    test('signalBatchComplete resolves outcome with success', () async {
      final c = StrictApplyCoordinator();
      final future = c.enterStrictMode();
      c.signalBatchComplete();
      final outcome = await future;
      expect(outcome, isA<ApplyOutcomeSuccess>());
      c.exitStrictMode();
    });

    test('dispose resolves pending outcome with failure', () async {
      final c = StrictApplyCoordinator();
      final future = c.enterStrictMode();
      c.dispose();

      final outcome = await future;
      expect(outcome, isA<ApplyOutcomeFailure>());
      expect(
        (outcome as ApplyOutcomeFailure).failure.message,
        'Strict apply coordinator disposed',
      );
      expect(c.isStrict, isFalse);
    });

    test(
      'exitStrictMode completes a still-pending outcome as success',
      () async {
        final c = StrictApplyCoordinator();
        final future = c.enterStrictMode();
        c.exitStrictMode();
        final outcome = await future;
        expect(outcome, isA<ApplyOutcomeSuccess>());
      },
    );

    // Regression: reproduces the Future.any race the latch pattern fixes.
    // If the failure signal is recorded BEFORE the awaiter is registered
    // (as happens when bootstrap's synchronous prologue emits failing
    // RemoteChanges before the joiner reaches its `await outcome`),
    // the outcome must still observe the failure — no lost signals.
    test('signalFailure before first await still observed', () async {
      final c = StrictApplyCoordinator();
      final future = c.enterStrictMode();
      c.signalFailure(
        const StrictApplyFailure(message: 'early', table: 'members'),
      );
      // Force a microtask hop to mimic the real caller awaiting something
      // else first, then finally awaiting outcome.
      await Future<void>.value();
      final outcome = await future;
      expect(outcome, isA<ApplyOutcomeFailure>());
      expect((outcome as ApplyOutcomeFailure).failure.table, 'members');
      c.exitStrictMode();
    });

    // Regression: first writer wins. Once signalFailure has resolved the
    // latch, a later signalBatchComplete must not flip the outcome to
    // success (or throw).
    test('first signal wins — later signals are ignored', () async {
      final c = StrictApplyCoordinator();
      final future = c.enterStrictMode();
      c.signalFailure(const StrictApplyFailure(message: 'first'));
      c.signalBatchComplete(); // must be a no-op
      c.signalFailure(const StrictApplyFailure(message: 'second'));
      final outcome = await future;
      expect(outcome, isA<ApplyOutcomeFailure>());
      expect((outcome as ApplyOutcomeFailure).failure.message, 'first');
      c.exitStrictMode();
    });

    test('outcome getter returns null when not in strict mode', () {
      final c = StrictApplyCoordinator();
      expect(c.outcome, isNull);
      c.enterStrictMode();
      expect(c.outcome, isNotNull);
      c.exitStrictMode();
      expect(c.outcome, isNull);
    });

    test('enterStrictMode resets the completer between attempts', () async {
      final c = StrictApplyCoordinator();
      // First attempt: signalled a failure, caller observed it.
      final first = c.enterStrictMode();
      c.signalFailure(const StrictApplyFailure(message: 'attempt-1'));
      expect(await first, isA<ApplyOutcomeFailure>());
      c.exitStrictMode();

      // Second attempt: fresh completer — a new signalBatchComplete must
      // resolve this completer, not the prior one.
      final second = c.enterStrictMode();
      expect(identical(first, second), isFalse);
      c.signalBatchComplete();
      expect(await second, isA<ApplyOutcomeSuccess>());
      c.exitStrictMode();
    });
  });
}
