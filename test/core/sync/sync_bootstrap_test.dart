import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;
import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';
import 'package:prism_plurality/core/sync/sync_bootstrap.dart';

class _FakePrismSyncHandle implements ffi.PrismSyncHandle {
  const _FakePrismSyncHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordedCall {
  _RecordedCall({
    required this.table,
    required this.entityId,
    required this.fieldsJson,
  });

  final String table;
  final String entityId;
  final String fieldsJson;

  Map<String, dynamic> get fields =>
      jsonDecode(fieldsJson) as Map<String, dynamic>;
}

void main() {
  group('DriftSyncEntity.entityIdFor', () {
    test('default returns row.id', () {
      final entity = DriftSyncEntity(
        tableName: 'foo',
        toSyncFields: (_) => const <String, dynamic>{},
        applyFields: (_, _) async {},
        hardDelete: (_) async {},
        readRow: (_) async => null,
        isDeleted: (_) async => false,
      );

      final row = MemberGroupRow(
        id: 'abc',
        name: 'n',
        displayOrder: 0,
        groupType: 0,
        isDeleted: false,
        syncSuppressed: false,
        createdAt: DateTime.utc(2024),
      );
      expect(entity.entityIdFor(row), 'abc');
    });

    test(
      'member_groups override returns canonical PK id when pluralkitUuid is set',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final entity = _entityFor(db, 'member_groups');

        final row = MemberGroupRow(
          id: 'pk-group-deadbeef',
          name: 'Core',
          displayOrder: 0,
          groupType: 0,
          isDeleted: false,
          syncSuppressed: false,
          createdAt: DateTime.utc(2024),
          pluralkitUuid: 'deadbeef',
        );

        expect(entity.entityIdFor(row), 'pk-group:deadbeef');
      },
    );

    test(
      'member_groups override falls back to row.id when pluralkitUuid is null',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final entity = _entityFor(db, 'member_groups');

        final row = MemberGroupRow(
          id: 'random-uuid',
          name: 'Local',
          displayOrder: 0,
          groupType: 0,
          isDeleted: false,
          syncSuppressed: false,
          createdAt: DateTime.utc(2024),
        );

        expect(entity.entityIdFor(row), 'random-uuid');
      },
    );

    test(
      'member_group_entries override returns sha256-hash id when both PK uuids present',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final entity = _entityFor(db, 'member_group_entries');

        const pkGroupUuid = 'g-uuid';
        const pkMemberUuid = 'm-uuid';
        const row = MemberGroupEntryRow(
          id: 'random-uuid',
          groupId: 'g',
          memberId: 'm',
          isDeleted: false,
          pkGroupUuid: pkGroupUuid,
          pkMemberUuid: pkMemberUuid,
        );

        final expected = sha256
            .convert(utf8.encode('$pkGroupUuid\u0000$pkMemberUuid'))
            .toString()
            .substring(0, 16);
        expect(entity.entityIdFor(row), expected);
      },
    );

    test(
      'member_group_entries override falls back to row.id when PK uuids missing',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final entity = _entityFor(db, 'member_group_entries');

        const row = MemberGroupEntryRow(
          id: 'random-uuid',
          groupId: 'g',
          memberId: 'm',
          isDeleted: false,
        );

        expect(entity.entityIdFor(row), 'random-uuid');
      },
    );
  });

  group('bootstrapExistingData', () {
    test(
      'emits PK-imported group under canonical entity_id, not the legacy Drift id',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        await db
            .into(db.memberGroups)
            .insert(
              MemberGroupsCompanion.insert(
                id: 'pk-group-abc-uuid',
                name: 'Friends',
                createdAt: DateTime.utc(2024),
                pluralkitUuid: const Value('abc-uuid'),
              ),
            );

        final calls = await _runBootstrap(db);

        final groupCalls = calls.where((c) => c.table == 'member_groups');
        expect(groupCalls, hasLength(1));
        expect(groupCalls.single.entityId, 'pk-group:abc-uuid');
      },
    );

    test('emits tombstones (rows with isDeleted=true)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'pk-group-deleted-uuid',
              name: 'Gone',
              createdAt: DateTime.utc(2024),
              pluralkitUuid: const Value('deleted-uuid'),
              isDeleted: const Value(true),
            ),
          );

      final calls = await _runBootstrap(db);

      final groupCalls = calls
          .where((c) => c.table == 'member_groups')
          .toList();
      expect(groupCalls, hasLength(1));
      expect(groupCalls.single.entityId, 'pk-group:deleted-uuid');
      expect(groupCalls.single.fields['is_deleted'], isTrue);
    });

    test('filters system_settings to id=singleton', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.systemSettingsTable)
          .insert(
            const SystemSettingsTableCompanion(
              id: Value('singleton'),
              systemName: Value('Real System'),
            ),
          );
      await db
          .into(db.systemSettingsTable)
          .insert(
            const SystemSettingsTableCompanion(
              id: Value('rogue'),
              systemName: Value('Rogue Row'),
            ),
          );

      final calls = await _runBootstrap(db);

      final settingsCalls = calls
          .where((c) => c.table == 'system_settings')
          .toList();
      expect(settingsCalls, hasLength(1));
      expect(settingsCalls.single.entityId, 'singleton');
    });

    test('throws if any row fails to emit', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: 'pk-group-partial-uuid',
              name: 'Partial',
              createdAt: DateTime.utc(2024),
              pluralkitUuid: const Value('partial-uuid'),
            ),
          );

      final adapter = buildSyncAdapterWithCompletion(db).adapter;

      await expectLater(
        bootstrapExistingData(
          handle: const _FakePrismSyncHandle(),
          db: db,
          adapter: adapter,
          recordCreate:
              ({
                required ffi.PrismSyncHandle handle,
                required String table,
                required String entityId,
                required String fieldsJson,
              }) async {
                throw StateError('ffi rejected fields');
              },
        ),
        throwsA(
          predicate(
            (Object error) =>
                error is StateError &&
                error.toString().contains('Bootstrap failed for 1 record') &&
                error.toString().contains(
                  'member_groups/pk-group:partial-uuid',
                ) &&
                error.toString().contains('ffi rejected fields'),
          ),
        ),
      );
    });
  });
}

DriftSyncEntity _entityFor(AppDatabase db, String tableName) {
  final adapter = buildSyncAdapterWithCompletion(db).adapter;
  return adapter.entities.singleWhere((e) => e.tableName == tableName);
}

Future<List<_RecordedCall>> _runBootstrap(AppDatabase db) async {
  final calls = <_RecordedCall>[];
  final adapter = buildSyncAdapterWithCompletion(db).adapter;
  await bootstrapExistingData(
    handle: const _FakePrismSyncHandle(),
    db: db,
    adapter: adapter,
    recordCreate:
        ({
          required ffi.PrismSyncHandle handle,
          required String table,
          required String entityId,
          required String fieldsJson,
        }) async {
          calls.add(
            _RecordedCall(
              table: table,
              entityId: entityId,
              fieldsJson: fieldsJson,
            ),
          );
        },
  );
  return calls;
}
