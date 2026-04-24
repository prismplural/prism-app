import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_group_sync_v2_catchup_service.dart';

MemberGroupsCompanion _group({
  required String id,
  required String name,
  required DateTime createdAt,
  String? pluralkitUuid,
  bool syncSuppressed = false,
}) => MemberGroupsCompanion.insert(
  id: id,
  name: name,
  createdAt: createdAt,
  pluralkitUuid: Value(pluralkitUuid),
  syncSuppressed: Value(syncSuppressed),
);

MembersCompanion _member({
  required String id,
  required String name,
  String? pluralkitUuid,
}) => MembersCompanion.insert(
  id: id,
  name: name,
  createdAt: DateTime.utc(2024, 1, 1),
  pluralkitUuid: Value(pluralkitUuid),
);

MemberGroupEntriesCompanion _entry({
  required String id,
  required String groupId,
  required String memberId,
  String? pkGroupUuid,
  String? pkMemberUuid,
}) => MemberGroupEntriesCompanion.insert(
  id: id,
  groupId: groupId,
  memberId: memberId,
  pkGroupUuid: Value(pkGroupUuid),
  pkMemberUuid: Value(pkMemberUuid),
);

String _canonicalEntryId(String pkGroupUuid, String pkMemberUuid) {
  final digest = sha256.convert(utf8.encode('$pkGroupUuid\x00$pkMemberUuid'));
  return digest.toString().substring(0, 16);
}

void main() {
  late AppDatabase db;
  late List<_RecordedOp> groupOps;
  late List<_RecordedOp> entryOps;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase(NativeDatabase.memory());
    groupOps = <_RecordedOp>[];
    entryOps = <_RecordedOp>[];
  });

  tearDown(() => db.close());

  PkGroupSyncV2CatchupService service() {
    return PkGroupSyncV2CatchupService(
      db: db,
      recordGroupUpdate:
          ({required table, required entityId, required fields}) async {
            groupOps.add(_RecordedOp(table, entityId, fields));
          },
      recordEntryCreate:
          ({required table, required entityId, required fields}) async {
            entryOps.add(_RecordedOp(table, entityId, fields));
          },
    );
  }

  test('does not mark complete before pk_group_sync_v2 is enabled', () async {
    await db.systemSettingsDao.getSettings();
    await db
        .into(db.memberGroups)
        .insert(
          _group(
            id: 'group-1',
            name: 'Cluster',
            createdAt: DateTime.utc(2024, 1, 1),
            pluralkitUuid: 'pk-group-1',
          ),
        );

    final result = await service().runOnce();

    expect(result.succeeded, isTrue);
    expect(result.groupsEmitted, 0);
    expect(groupOps, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PkGroupSyncV2CatchupService.flagKey), isNot(isTrue));
  });

  test(
    'emits after an earlier disabled no-op once cutover flag flips',
    () async {
      await db.systemSettingsDao.getSettings();
      await db
          .into(db.memberGroups)
          .insert(
            _group(
              id: 'pk-group-local-1',
              name: 'Cluster',
              createdAt: DateTime.utc(2024, 1, 1),
              pluralkitUuid: 'pk-group-1',
            ),
          );

      final first = await service().runOnce();
      expect(first.groupsEmitted, 0);
      expect(groupOps, isEmpty);

      await db.systemSettingsDao.updatePkGroupSyncV2Enabled(true);
      final second = await service().runOnce();

      expect(second.groupsEmitted, 1);
      expect(groupOps.single.entityId, 'pk-group:pk-group-1');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PkGroupSyncV2CatchupService.flagKey), isTrue);
    },
  );

  test('catches up PK groups and entries with canonical IDs', () async {
    await db.systemSettingsDao.getSettings();
    await db.systemSettingsDao.updatePkGroupSyncV2Enabled(true);

    await db
        .into(db.members)
        .insert(
          _member(id: 'member-a', name: 'Alice', pluralkitUuid: 'pk-member-a'),
        );
    await db
        .into(db.memberGroups)
        .insert(
          _group(
            id: 'pk-group-local-1',
            name: 'Cluster',
            createdAt: DateTime.utc(2024, 1, 1),
            pluralkitUuid: 'pk-group-1',
          ),
        );
    await db
        .into(db.memberGroupEntries)
        .insert(
          _entry(
            id: 'legacy-entry',
            groupId: 'pk-group-local-1',
            memberId: 'member-a',
          ),
        );

    final result = await service().runOnce();

    expect(result.groupsEmitted, 1);
    expect(result.entriesEmitted, 1);
    expect(groupOps.single.table, 'member_groups');
    expect(groupOps.single.entityId, 'pk-group:pk-group-1');
    expect(groupOps.single.fields['pluralkit_uuid'], 'pk-group-1');
    expect(entryOps.single.table, 'member_group_entries');
    expect(
      entryOps.single.entityId,
      _canonicalEntryId('pk-group-1', 'pk-member-a'),
    );
    expect(entryOps.single.fields['pk_group_uuid'], 'pk-group-1');
    expect(entryOps.single.fields['pk_member_uuid'], 'pk-member-a');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PkGroupSyncV2CatchupService.flagKey), isTrue);
  });

  test('skips suppressed groups and their entries', () async {
    await db.systemSettingsDao.getSettings();
    await db.systemSettingsDao.updatePkGroupSyncV2Enabled(true);

    await db
        .into(db.members)
        .insert(
          _member(id: 'member-a', name: 'Alice', pluralkitUuid: 'pk-member-a'),
        );
    await db
        .into(db.memberGroups)
        .insert(
          _group(
            id: 'suppressed',
            name: 'Suppressed',
            createdAt: DateTime.utc(2024, 1, 1),
            pluralkitUuid: 'pk-group-1',
            syncSuppressed: true,
          ),
        );
    await db
        .into(db.memberGroupEntries)
        .insert(
          _entry(id: 'entry-a', groupId: 'suppressed', memberId: 'member-a'),
        );

    final result = await service().runOnce();

    expect(result.groupsEmitted, 0);
    expect(result.entriesEmitted, 0);
    expect(groupOps, isEmpty);
    expect(entryOps, isEmpty);
  });

  test('is idempotent via SharedPreferences flag', () async {
    await db.systemSettingsDao.getSettings();
    await db.systemSettingsDao.updatePkGroupSyncV2Enabled(true);
    await db
        .into(db.memberGroups)
        .insert(
          _group(
            id: 'pk-group-local-1',
            name: 'Cluster',
            createdAt: DateTime.utc(2024, 1, 1),
            pluralkitUuid: 'pk-group-1',
          ),
        );

    final first = await service().runOnce();
    final second = await service().runOnce();

    expect(first.groupsEmitted, 1);
    expect(second.alreadyCompleted, isTrue);
    expect(groupOps, hasLength(1));
  });

  test('does not mark complete after emit failure and retries later', () async {
    await db.systemSettingsDao.getSettings();
    await db.systemSettingsDao.updatePkGroupSyncV2Enabled(true);
    await db
        .into(db.memberGroups)
        .insert(
          _group(
            id: 'pk-group-local-1',
            name: 'Cluster',
            createdAt: DateTime.utc(2024, 1, 1),
            pluralkitUuid: 'pk-group-1',
          ),
        );

    var shouldThrow = true;
    PkGroupSyncV2CatchupService flakyService() {
      return PkGroupSyncV2CatchupService(
        db: db,
        recordGroupUpdate:
            ({required table, required entityId, required fields}) async {
              if (shouldThrow) throw StateError('temporary sync failure');
              groupOps.add(_RecordedOp(table, entityId, fields));
            },
        recordEntryCreate:
            ({required table, required entityId, required fields}) async {
              entryOps.add(_RecordedOp(table, entityId, fields));
            },
      );
    }

    final first = await flakyService().runOnce();
    final prefs = await SharedPreferences.getInstance();
    expect(first.error, contains('temporary sync failure'));
    expect(prefs.getBool(PkGroupSyncV2CatchupService.flagKey), isNot(isTrue));
    expect(groupOps, isEmpty);

    shouldThrow = false;
    final second = await flakyService().runOnce();

    expect(second.succeeded, isTrue);
    expect(second.groupsEmitted, 1);
    expect(groupOps.single.entityId, 'pk-group:pk-group-1');
    expect(prefs.getBool(PkGroupSyncV2CatchupService.flagKey), isTrue);
  });
}

class _RecordedOp {
  const _RecordedOp(this.table, this.entityId, this.fields);

  final String table;
  final String entityId;
  final Map<String, dynamic> fields;
}
