import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';

MemberGroupEntriesCompanion _entry({
  required String id,
  required String groupId,
  required String memberId,
  String? pkGroupUuid,
  String? pkMemberUuid,
  bool isDeleted = false,
}) => MemberGroupEntriesCompanion.insert(
  id: id,
  groupId: groupId,
  memberId: memberId,
  pkGroupUuid: Value(pkGroupUuid),
  pkMemberUuid: Value(pkMemberUuid),
  isDeleted: Value(isDeleted),
);

String _canonicalEntryId(String pkGroupUuid, String pkMemberUuid) {
  final joined = '$pkGroupUuid\x00$pkMemberUuid';
  final digest = sha256.convert(utf8.encode(joined));
  return digest.toString().substring(0, 16);
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test(
    'canonicalizePkBackedEntryIds rewrites legacy id to canonical when no tombstone exists',
    () async {
      const pkGroupUuid = 'pk-group-1';
      const pkMemberUuid = 'pk-member-a';
      final canonical = _canonicalEntryId(pkGroupUuid, pkMemberUuid);

      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'random-legacy',
              groupId: 'group-a',
              memberId: 'member-a',
              pkGroupUuid: pkGroupUuid,
              pkMemberUuid: pkMemberUuid,
            ),
          );

      final result = await db.memberGroupsDao.canonicalizePkBackedEntryIds();

      expect(result.rewritten, 1);
      expect(result.revivedTombstones, 0);
      expect(result.softDeletedLegacyConflicts, 0);

      final legacyAfter = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('random-legacy'))).getSingleOrNull();
      expect(legacyAfter, isNull);

      final canonicalRow = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(canonical))).getSingle();
      expect(canonicalRow.groupId, 'group-a');
      expect(canonicalRow.memberId, 'member-a');
      expect(canonicalRow.pkGroupUuid, pkGroupUuid);
      expect(canonicalRow.pkMemberUuid, pkMemberUuid);
      expect(canonicalRow.isDeleted, isFalse);
    },
  );

  test(
    'canonicalizePkBackedEntryIds revives canonical tombstone and soft-deletes legacy active',
    () async {
      const pkGroupUuid = 'pk-group-1';
      const pkMemberUuid = 'pk-member-a';
      final canonical = _canonicalEntryId(pkGroupUuid, pkMemberUuid);

      // Seed a legacy-id active row and a tombstoned canonical row for the
      // same logical edge.
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'random-legacy',
              groupId: 'group-a',
              memberId: 'member-a',
              pkGroupUuid: pkGroupUuid,
              pkMemberUuid: pkMemberUuid,
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: canonical,
              groupId: 'group-a',
              memberId: 'member-a',
              pkGroupUuid: pkGroupUuid,
              pkMemberUuid: pkMemberUuid,
              isDeleted: true,
            ),
          );

      final result = await db.memberGroupsDao.canonicalizePkBackedEntryIds();

      expect(result.rewritten, 0);
      expect(result.revivedTombstones, 1);
      expect(result.softDeletedLegacyConflicts, 1);

      // Canonical row now active.
      final canonicalRow = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(canonical))).getSingle();
      expect(canonicalRow.isDeleted, isFalse);
      expect(canonicalRow.groupId, 'group-a');
      expect(canonicalRow.memberId, 'member-a');
      expect(canonicalRow.pkGroupUuid, pkGroupUuid);
      expect(canonicalRow.pkMemberUuid, pkMemberUuid);

      // Legacy row soft-deleted.
      final legacyRow = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('random-legacy'))).getSingle();
      expect(legacyRow.isDeleted, isTrue);

      // Exactly one active row for the logical edge.
      final active =
          await (db.select(db.memberGroupEntries)..where(
                (t) =>
                    t.groupId.equals('group-a') &
                    t.memberId.equals('member-a') &
                    t.isDeleted.equals(false),
              ))
              .get();
      expect(active, hasLength(1));
      expect(active.single.id, canonical);
    },
  );

  test('canonicalizePkBackedEntryIds is idempotent', () async {
    const pkGroupUuid = 'pk-group-1';
    const pkMemberUuid = 'pk-member-a';

    await db
        .into(db.memberGroupEntries)
        .insert(
          _entry(
            id: 'random-legacy',
            groupId: 'group-a',
            memberId: 'member-a',
            pkGroupUuid: pkGroupUuid,
            pkMemberUuid: pkMemberUuid,
          ),
        );

    final firstPass = await db.memberGroupsDao.canonicalizePkBackedEntryIds();
    expect(firstPass.rewritten, 1);
    expect(firstPass.revivedTombstones, 0);
    expect(firstPass.softDeletedLegacyConflicts, 0);

    final secondPass = await db.memberGroupsDao.canonicalizePkBackedEntryIds();
    expect(secondPass.rewritten, 0);
    expect(secondPass.revivedTombstones, 0);
    expect(secondPass.softDeletedLegacyConflicts, 0);
  });

  test(
    'canonicalizePkBackedEntryIds skips entries with null pk_group_uuid or pk_member_uuid',
    () async {
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'plain-entry',
              groupId: 'group-a',
              memberId: 'member-a',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'group-only-entry',
              groupId: 'group-a',
              memberId: 'member-b',
              pkGroupUuid: 'pk-group-1',
            ),
          );
      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: 'member-only-entry',
              groupId: 'group-a',
              memberId: 'member-c',
              pkMemberUuid: 'pk-member-c',
            ),
          );

      final result = await db.memberGroupsDao.canonicalizePkBackedEntryIds();

      expect(result.rewritten, 0);
      expect(result.revivedTombstones, 0);
      expect(result.softDeletedLegacyConflicts, 0);

      final plain = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('plain-entry'))).getSingle();
      expect(plain.id, 'plain-entry');

      final groupOnly = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('group-only-entry'))).getSingle();
      expect(groupOnly.id, 'group-only-entry');

      final memberOnly = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals('member-only-entry'))).getSingle();
      expect(memberOnly.id, 'member-only-entry');
    },
  );

  test(
    'canonicalizePkBackedEntryIds skips entries whose id is already canonical',
    () async {
      const pkGroupUuid = 'pk-group-1';
      const pkMemberUuid = 'pk-member-a';
      final canonical = _canonicalEntryId(pkGroupUuid, pkMemberUuid);

      await db
          .into(db.memberGroupEntries)
          .insert(
            _entry(
              id: canonical,
              groupId: 'group-a',
              memberId: 'member-a',
              pkGroupUuid: pkGroupUuid,
              pkMemberUuid: pkMemberUuid,
            ),
          );

      final result = await db.memberGroupsDao.canonicalizePkBackedEntryIds();
      expect(result.rewritten, 0);
      expect(result.revivedTombstones, 0);
      expect(result.softDeletedLegacyConflicts, 0);

      final row = await (db.select(
        db.memberGroupEntries,
      )..where((t) => t.id.equals(canonical))).getSingle();
      expect(row.groupId, 'group-a');
      expect(row.memberId, 'member-a');
      expect(row.isDeleted, isFalse);
    },
  );
}
