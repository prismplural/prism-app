import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/data/repositories/drift_member_repository.dart';

/// task_70731ec1: unlinking a member (clearPluralKitLink) must GC the inbound
/// PK-identity redirect aliases that pointed at it — they would otherwise
/// accumulate across unlink/re-link cycles. This is hygiene (the apply layer
/// re-validates a stale alias), and unlike a delete it must NOT tombstone the
/// legacy ids (the member lives on).
void main() {
  late AppDatabase db;
  late DriftMemberRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftMemberRepository(db.membersDao, null);
  });
  tearDown(() => db.close());

  Future<int> aliasCountForTarget(String memberId) async {
    final rows = await db
        .customSelect(
          'SELECT 1 FROM pk_identity_sync_aliases WHERE target_row_id = ?',
          variables: [Variable<String>(memberId)],
        )
        .get();
    return rows.length;
  }

  test('clearPluralKitLink purges the member inbound identity aliases',
      () async {
    await db.into(db.members).insert(
          MembersCompanion.insert(
            id: 'member-1',
            name: 'Ada',
            createdAt: DateTime.utc(2026, 6),
            pluralkitUuid: const Value('U'),
            pluralkitId: const Value('abcde'),
          ),
        );
    // A redirect alias planted on some device: legacy id "old-id" → member-1
    // for identity (U, abcde).
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'old-id',
      pkUuid: 'U',
      pkId: 'abcde',
      memberId: 'member-1',
      targetRowId: 'member-1',
    );
    expect(await aliasCountForTarget('member-1'), 1);

    await repo.clearPluralKitLink('member-1');

    expect(await aliasCountForTarget('member-1'), 0,
        reason: 'unlinking GCs the now-stale inbound aliases');
    // The member SURVIVES — unlink, not delete.
    final m = await (db.select(db.members)
          ..where((t) => t.id.equals('member-1')))
        .getSingle();
    expect(m.isDeleted, isFalse, reason: 'unlink must not tombstone the member');
    expect(m.pluralkitUuid, isNull);
    expect(m.pluralkitId, isNull);
  });

  test('clearPluralKitLink on an unlinked member is a no-op for aliases',
      () async {
    await db.into(db.members).insert(
          MembersCompanion.insert(
            id: 'member-2',
            name: 'Bo',
            createdAt: DateTime.utc(2026, 6),
          ),
        );
    // No identity → nothing to purge, and must not throw.
    await repo.clearPluralKitLink('member-2');
    expect(await aliasCountForTarget('member-2'), 0);
  });

  test(
      'clearPluralKitLink does not purge a different live member alias carrying '
      'a recycled short id (uuid-only purge)', () async {
    // A holds uuid U_A + short id "abcde". B holds uuid U_B, and an alias
    // redirects a legacy id onto B keyed by B's uuid AND the SAME short id
    // (recycled from A under Premium). Unlinking A must not drop B's alias.
    await db.into(db.members).insert(
          MembersCompanion.insert(
            id: 'member-a',
            name: 'A',
            createdAt: DateTime.utc(2026, 6),
            pluralkitUuid: const Value('U_A'),
            pluralkitId: const Value('abcde'),
          ),
        );
    await db.into(db.members).insert(
          MembersCompanion.insert(
            id: 'member-b',
            name: 'B',
            createdAt: DateTime.utc(2026, 6),
            pluralkitUuid: const Value('U_B'),
          ),
        );
    await db.pkIdentitySyncAliasesDao.upsertAlias(
      entityTable: 'members',
      legacyEntityId: 'b-legacy',
      pkUuid: 'U_B',
      pkId: 'abcde', // recycled from A
      targetRowId: 'member-b',
    );

    await repo.clearPluralKitLink('member-a');

    expect(await aliasCountForTarget('member-b'), 1,
        reason: "B's alias (keyed by B's uuid) survives A's unlink despite the "
            'shared recycled short id');
  });
}
