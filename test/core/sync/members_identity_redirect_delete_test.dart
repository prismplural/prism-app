import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

/// F23: the PK-identity apply redirect must be delete-symmetric. When an
/// incoming op for legacy id X is redirected onto a different active local row
/// Y (same PK identity), a later delete for X must resolve to Y — both via the
/// hard-delete (engine `is_delete`) path and the fields-borne `is_deleted=true`
/// tombstone path — and the recorded alias must be purged on resolution.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  dynamic entityFor(String table) =>
      buildSyncAdapterWithCompletion(db).adapter.entities
          .singleWhere((entity) => entity.tableName == table);

  Map<String, dynamic> memberFields({
    required String name,
    String? pkUuid,
    String? pkId,
    bool isDeleted = false,
    DateTime? createdAt,
  }) {
    return <String, dynamic>{
      'name': name,
      'emoji': '*',
      'is_active': true,
      'created_at': (createdAt ?? DateTime.utc(2026, 6)).toIso8601String(),
      'display_order': 0,
      'is_admin': false,
      'custom_color_enabled': false,
      'pluralkit_uuid': pkUuid,
      'pluralkit_id': pkId,
      'markdown_enabled': true,
      'profile_header_source': 1,
      'profile_header_layout': 0,
      'profile_header_visible': true,
      'name_style_font': 0,
      'name_style_bold': true,
      'name_style_italic': false,
      'name_style_color_mode': 0,
      'pluralkit_sync_ignored': false,
      'is_always_fronting': false,
      'is_deleted': isDeleted,
    };
  }

  Future<int> aliasCount(String table) async {
    final rows = await db
        .customSelect(
          'SELECT 1 FROM pk_identity_sync_aliases WHERE entity_table = ?',
          variables: [Variable<String>(table)],
        )
        .get();
    return rows.length;
  }

  group('members redirect delete-symmetry', () {
    test('redirect records an alias for the legacy id', () async {
      final members = entityFor('members');
      // Active holder under idA.
      await members.applyFields(
        'idA',
        memberFields(name: 'Ada', pkUuid: 'U', pkId: 'abcde'),
      );
      // Incoming op for idB with the same identity is redirected onto idA.
      await members.applyFields(
        'idB',
        memberFields(name: 'Ada edited', pkUuid: 'U', pkId: 'abcde'),
      );

      final rows = await db.select(db.members).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'idA');

      final alias = await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
        'members',
        'idB',
      );
      expect(alias, isNotNull);
      expect(alias!.targetRowId, 'idA');
      expect(alias.pkUuid, 'U');
      expect(alias.pkId, 'abcde');
    });

    test('hardDelete of the redirected id deletes the holder and purges the '
        'alias', () async {
      final members = entityFor('members');
      await members.applyFields(
        'idA',
        memberFields(name: 'Ada', pkUuid: 'U', pkId: 'abcde'),
      );
      await members.applyFields(
        'idB',
        memberFields(name: 'Ada', pkUuid: 'U', pkId: 'abcde'),
      );

      await members.hardDelete('idB');

      final rows = await db.select(db.members).get();
      expect(rows, isEmpty, reason: 'holder idA must be deleted');
      expect(await aliasCount('members'), 0, reason: 'alias purged');
    });

    test('fields-tombstone of the redirected id tombstones the holder with no '
        'stub row', () async {
      final members = entityFor('members');
      await members.applyFields(
        'idA',
        memberFields(name: 'Ada', pkUuid: 'U', pkId: 'abcde'),
      );
      await members.applyFields(
        'idB',
        memberFields(name: 'Ada', pkUuid: 'U', pkId: 'abcde'),
      );

      await members.applyFields(
        'idB',
        memberFields(name: 'Ada', pkUuid: 'U', pkId: 'abcde', isDeleted: true),
      );

      final rows = await db.select(db.members).get();
      expect(rows, hasLength(1), reason: 'no stub row under idB');
      expect(rows.single.id, 'idA');
      expect(rows.single.isDeleted, isTrue, reason: 'holder tombstoned');
    });

    test('a tombstone for an id with NO recorded alias keeps the stub-insert '
        'behavior and the active holder survives', () async {
      final members = entityFor('members');
      // Active holder; then a stale tombstone arrives under a DIFFERENT id with
      // the same identity but no alias was ever recorded for it (it never went
      // through the non-tombstone redirect path).
      await members.applyFields(
        'active-holder',
        memberFields(name: 'Active holder', pkUuid: 'U', pkId: 'abcde'),
      );
      await members.applyFields(
        'stale-tombstone',
        memberFields(
          name: 'Stale',
          pkUuid: 'U',
          pkId: 'abcde',
          isDeleted: true,
        ),
      );

      final rows = await db.select(db.members).get();
      expect(rows, hasLength(2));
      final active = rows.singleWhere((row) => row.id == 'active-holder');
      final tombstone = rows.singleWhere((row) => row.id == 'stale-tombstone');
      expect(active.isDeleted, isFalse);
      expect(active.pluralkitUuid, 'U');
      expect(tombstone.isDeleted, isTrue);
      expect(tombstone.pluralkitUuid, isNull);
    });

    test('redirect + delete records and purges a pkId-only alias (pk_uuid '
        'NULL), and the holder survives a re-import', () async {
      // Exercises the OR-matching in getByIdentity / the matchScore path keyed
      // on pluralkit_id only (no uuid).
      final members = entityFor('members');
      await members.applyFields(
        'idA',
        memberFields(name: 'Ada', pkId: 'abcde'),
      );
      await members.applyFields(
        'idB',
        memberFields(name: 'Ada', pkId: 'abcde'),
      );

      final alias = await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
        'members',
        'idB',
      );
      expect(alias, isNotNull);
      expect(alias!.pkUuid, isNull);
      expect(alias.pkId, 'abcde');
      expect(alias.targetRowId, 'idA');

      await members.hardDelete('idB');
      expect(await db.select(db.members).get(), isEmpty);
      expect(await aliasCount('members'), 0, reason: 'pkId-only alias purged');
    });

    test('a stale alias never kills a re-imported same-identity row — the '
        'post-delete PK re-import survives a redelivered legacy-id delete '
        '(realistic historical pk.created shape)', () async {
      // Blocker trace (device B): B imported its own row idB; A's row idA was
      // redirected onto idB at pairing, recording alias(legacy=idA -> idB).
      // The re-import (idC) carries the SAME historical pk.created timestamp as
      // every incarnation (createMember writes pk.created verbatim), so the
      // temporal bound on the holder resolver CANNOT discriminate it — the
      // protection here is the target-row purge that drops the idA->idB alias
      // when its recorded holder idB is hard-deleted.
      final members = entityFor('members');
      await members.applyFields(
        'idB',
        memberFields(
          name: 'Ada',
          pkUuid: 'U',
          pkId: 'abcde',
          createdAt: DateTime.utc(2024, 1, 1),
        ),
      );
      await members.applyFields(
        'idA',
        memberFields(
          name: 'Ada',
          pkUuid: 'U',
          pkId: 'abcde',
          createdAt: DateTime.utc(2024, 1, 1),
        ),
      );
      final alias = await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
        'members',
        'idA',
      );
      expect(alias, isNotNull, reason: 'alias(legacy=idA -> idB) recorded');
      expect(alias!.targetRowId, 'idB');

      // A deletes; B applies the fan-out delete of idB FIRST (exact-id). The
      // terminal hardDelete purges every alias whose target is the dying idB,
      // so the idA->idB alias is gone immediately — no race window remains.
      await members.hardDelete('idB');
      expect(
        await db.select(db.members).get(),
        isEmpty,
        reason: 'idB hard-deleted',
      );
      expect(
        await db.pkIdentitySyncAliasesDao.getByLegacyEntityId('members', 'idA'),
        isNull,
        reason: 'target-row purge drops the alias when holder idB dies',
      );

      // The user re-imports the identity: a NEW active row idC with the SAME
      // historical pk.created timestamp as the original incarnation.
      await members.applyFields(
        'idC',
        memberFields(
          name: 'Ada reimported',
          pkUuid: 'U',
          pkId: 'abcde',
          createdAt: DateTime.utc(2024, 1, 1),
        ),
      );
      expect((await db.select(db.members).get()).single.id, 'idC');

      // The delayed legacy-id delete for idA finally arrives. The alias is gone,
      // so the holder resolver returns null and the delete no-ops — it must NOT
      // re-resolve the stale identity onto the newer idC and kill it.
      await members.hardDelete('idA');
      final survivors = await db.select(db.members).get();
      expect(
        survivors.map((r) => r.id),
        ['idC'],
        reason: 'the re-imported row idC must survive the stale delete',
      );
      expect(survivors.single.isDeleted, isFalse);
    });

    test('a stale alias never kills a re-imported same-identity row — the '
        'post-delete PK re-import survives a redelivered legacy-id '
        'fields-tombstone (realistic historical pk.created shape)', () async {
      final members = entityFor('members');
      await members.applyFields(
        'idB',
        memberFields(
          name: 'Ada',
          pkUuid: 'U',
          pkId: 'abcde',
          createdAt: DateTime.utc(2024, 1, 1),
        ),
      );
      await members.applyFields(
        'idA',
        memberFields(
          name: 'Ada',
          pkUuid: 'U',
          pkId: 'abcde',
          createdAt: DateTime.utc(2024, 1, 1),
        ),
      );
      // Holder idB tombstoned via a fields-borne is_deleted=true (not hardDelete)
      // — this is the existing-row fields-tombstone terminal path. It must purge
      // every alias targeting idB just as the hardDelete branch does.
      await members.applyFields(
        'idB',
        memberFields(name: 'Ada', pkUuid: 'U', pkId: 'abcde', isDeleted: true),
      );
      expect(
        await db.pkIdentitySyncAliasesDao.getByLegacyEntityId('members', 'idA'),
        isNull,
        reason: 'target-row purge drops the alias when holder idB is tombstoned',
      );

      await members.applyFields(
        'idC',
        memberFields(
          name: 'Ada reimported',
          pkUuid: 'U',
          pkId: 'abcde',
          createdAt: DateTime.utc(2024, 1, 1),
        ),
      );

      // The delayed legacy-id fields-tombstone for idA arrives. The alias is gone
      // so it cannot resolve onto idC; idC stays active and a stub idA row is
      // inserted per the no-resolvable-holder path.
      await members.applyFields(
        'idA',
        memberFields(name: 'Ada', pkUuid: 'U', pkId: 'abcde', isDeleted: true),
      );

      final rows = await db.select(db.members).get();
      final idC = rows.singleWhere((r) => r.id == 'idC');
      expect(
        idC.isDeleted,
        isFalse,
        reason: 'the re-imported row idC must survive the stale tombstone',
      );
    });

    test('FAN-IN: a SIBLING alias onto a holder killed via the resolved-holder '
        'delete path does not survive to re-kill a re-import', () async {
      // F23 re-review blocker probe (3-device fan-in). idC owns the row; both
      // idA and idB were redirected onto it at pairing (aliases idA->idC and
      // idB->idC), all sharing the realistic historical pk.created timestamp.
      // The fix must purge BOTH inbound aliases when idC dies via the RESOLVED-
      // HOLDER hardDelete path (delete of legacy idA, no exact-id row) — not just
      // the one being resolved — or the surviving idB alias re-resolves the stale
      // identity onto a re-import and hard-deletes it with no emission.
      final members = entityFor('members');
      final created = DateTime.utc(2024, 1, 1);
      // Holder idC materializes first; idA and idB redirect onto it.
      await members.applyFields(
        'idC',
        memberFields(name: 'Ada', pkUuid: 'U', pkId: 'abcde', createdAt: created),
      );
      await members.applyFields(
        'idA',
        memberFields(name: 'Ada', pkUuid: 'U', pkId: 'abcde', createdAt: created),
      );
      await members.applyFields(
        'idB',
        memberFields(name: 'Ada', pkUuid: 'U', pkId: 'abcde', createdAt: created),
      );
      expect(
        (await db.pkIdentitySyncAliasesDao.getByIdentity(
          'members',
          pkUuid: 'U',
          pkId: 'abcde',
        )).map((a) => a.legacyEntityId).toSet(),
        {'idA', 'idB'},
        reason: 'both idA and idB redirected onto holder idC',
      );

      // The delayed delete of legacy idA arrives with NO exact-id row → resolves
      // the identity to active holder idC and deletes it (resolved-holder path).
      await members.hardDelete('idA');
      expect(
        await db.select(db.members).get(),
        isEmpty,
        reason: 'holder idC deleted via the resolved-holder path',
      );
      expect(
        await aliasCount('members'),
        0,
        reason: 'identity-keyed purge drops the SIBLING idB alias too, not just '
            'the resolved idA alias',
      );

      // Re-import the identity with the same historical timestamp.
      await members.applyFields(
        'idD',
        memberFields(
          name: 'Ada reimported',
          pkUuid: 'U',
          pkId: 'abcde',
          createdAt: created,
        ),
      );
      expect((await db.select(db.members).get()).single.id, 'idD');

      // The delayed sibling delete of legacy idB arrives. With idB's alias gone,
      // it must no-op and leave the re-imported idD alive.
      await members.hardDelete('idB');
      final survivors = await db.select(db.members).get();
      expect(
        survivors.map((r) => r.id),
        ['idD'],
        reason: 're-imported idD must survive the stale sibling delete',
      );
      expect(survivors.single.isDeleted, isFalse);
    });
  });

  Map<String, dynamic> frontingFields({
    required String memberId,
    String? pkUuid,
    bool isDeleted = false,
    DateTime? startTime,
  }) {
    return <String, dynamic>{
      'start_time': (startTime ?? DateTime.utc(2026, 6, 1, 8))
          .toIso8601String(),
      'end_time': null,
      'member_id': memberId,
      'session_type': 0,
      'is_health_kit_import': false,
      'pluralkit_uuid': pkUuid,
      'is_deleted': isDeleted,
    };
  }

  group('fronting_sessions redirect delete-symmetry', () {
    test('redirect records an alias keyed on (pluralkit_uuid, member_id)',
        () async {
      final fronting = entityFor('fronting_sessions');
      await fronting.applyFields(
        'sessA',
        frontingFields(memberId: 'm1', pkUuid: 'SW'),
      );
      await fronting.applyFields(
        'sessB',
        frontingFields(memberId: 'm1', pkUuid: 'SW'),
      );

      final rows = await db.select(db.frontingSessions).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'sessA');

      final alias = await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
        'fronting_sessions',
        'sessB',
      );
      expect(alias, isNotNull);
      expect(alias!.targetRowId, 'sessA');
      expect(alias.pkUuid, 'SW');
      expect(alias.memberId, 'm1');
    });

    test('hardDelete of the redirected session id deletes the holder and '
        'purges the alias', () async {
      final fronting = entityFor('fronting_sessions');
      await fronting.applyFields(
        'sessA',
        frontingFields(memberId: 'm1', pkUuid: 'SW'),
      );
      await fronting.applyFields(
        'sessB',
        frontingFields(memberId: 'm1', pkUuid: 'SW'),
      );

      await fronting.hardDelete('sessB');

      final rows = await db.select(db.frontingSessions).get();
      expect(rows, isEmpty);
      expect(await aliasCount('fronting_sessions'), 0);
    });

    test('fields-tombstone of the redirected session id tombstones the holder '
        'instead of early-returning', () async {
      final fronting = entityFor('fronting_sessions');
      await fronting.applyFields(
        'sessA',
        frontingFields(memberId: 'm1', pkUuid: 'SW'),
      );
      await fronting.applyFields(
        'sessB',
        frontingFields(memberId: 'm1', pkUuid: 'SW'),
      );

      await fronting.applyFields(
        'sessB',
        frontingFields(memberId: 'm1', pkUuid: 'SW', isDeleted: true),
      );

      final rows = await db.select(db.frontingSessions).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'sessA');
      expect(rows.single.isDeleted, isTrue);
    });

    test('a tombstone for an id with NO recorded alias still early-returns '
        '(no row created)', () async {
      final fronting = entityFor('fronting_sessions');
      await fronting.applyFields(
        'sessB',
        frontingFields(memberId: 'm1', pkUuid: 'SW', isDeleted: true),
      );

      final rows = await db.select(db.frontingSessions).get();
      expect(rows, isEmpty);
    });

    test('a stale alias never kills a re-imported same-identity session — the '
        'post-delete re-import survives a redelivered legacy-id delete and '
        'tombstone (realistic historical switch-start shape)', () async {
      final fronting = entityFor('fronting_sessions');
      // B's own session sessB; A's sessA redirected onto it. A switch re-import
      // sets start_time = switchEntry.timestamp, identical across incarnations,
      // so the temporal bound cannot tell a re-import apart — the protection is
      // the target-row purge dropping the sessA->sessB alias when sessB dies.
      await fronting.applyFields(
        'sessB',
        frontingFields(
          memberId: 'm1',
          pkUuid: 'SW',
          startTime: DateTime.utc(2024, 1, 1, 8),
        ),
      );
      await fronting.applyFields(
        'sessA',
        frontingFields(
          memberId: 'm1',
          pkUuid: 'SW',
          startTime: DateTime.utc(2024, 1, 1, 8),
        ),
      );
      expect(
        await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
          'fronting_sessions',
          'sessA',
        ),
        isNotNull,
      );

      // Fan-out delete of sessB lands first; the terminal hardDelete purges the
      // sessA->sessB alias along with the dying holder — no race window.
      await fronting.hardDelete('sessB');
      expect(await db.select(db.frontingSessions).get(), isEmpty);
      expect(
        await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
          'fronting_sessions',
          'sessA',
        ),
        isNull,
        reason: 'target-row purge drops the alias when holder sessB dies',
      );

      // Re-import: a NEW session sessC with the SAME historical switch start.
      await fronting.applyFields(
        'sessC',
        frontingFields(
          memberId: 'm1',
          pkUuid: 'SW',
          startTime: DateTime.utc(2024, 1, 1, 8),
        ),
      );
      expect((await db.select(db.frontingSessions).get()).single.id, 'sessC');

      // The delayed legacy-id delete for sessA must not kill the re-imported
      // sessC — the alias is gone so the resolver returns null and it no-ops.
      await fronting.hardDelete('sessA');
      expect(
        (await db.select(db.frontingSessions).get()).map((r) => r.id),
        ['sessC'],
        reason: 're-imported sessC survives the stale delete',
      );

      // And a redelivered legacy-id fields-tombstone for sessA must not either.
      await fronting.applyFields(
        'sessA',
        frontingFields(memberId: 'm1', pkUuid: 'SW', isDeleted: true),
      );
      final survivors = await db.select(db.frontingSessions).get();
      final sessC = survivors.singleWhere((r) => r.id == 'sessC');
      expect(
        sessC.isDeleted,
        isFalse,
        reason: 're-imported sessC survives the stale tombstone',
      );
    });

    test('FAN-IN: a SIBLING alias onto a session killed via the resolved-holder '
        'delete path does not survive to re-kill a re-import', () async {
      // F23 re-review blocker probe (fronting variant). sessC owns the session;
      // both sessA and sessB redirect onto it (aliases sessA->sessC and
      // sessB->sessC), all sharing the historical switch-start time. Killing
      // sessC via the resolved-holder hardDelete path (delete of legacy sessA,
      // no exact-id row) must purge BOTH inbound aliases by identity, else the
      // surviving sessB alias re-kills a re-import.
      final fronting = entityFor('fronting_sessions');
      final start = DateTime.utc(2024, 1, 1, 8);
      await fronting.applyFields(
        'sessC',
        frontingFields(memberId: 'm1', pkUuid: 'SW', startTime: start),
      );
      await fronting.applyFields(
        'sessA',
        frontingFields(memberId: 'm1', pkUuid: 'SW', startTime: start),
      );
      await fronting.applyFields(
        'sessB',
        frontingFields(memberId: 'm1', pkUuid: 'SW', startTime: start),
      );
      expect(
        (await db.pkIdentitySyncAliasesDao.getByIdentity(
          'fronting_sessions',
          pkUuid: 'SW',
          memberId: 'm1',
        )).map((a) => a.legacyEntityId).toSet(),
        {'sessA', 'sessB'},
        reason: 'both sessA and sessB redirected onto holder sessC',
      );

      // Delayed delete of legacy sessA → no exact-id row → resolves identity to
      // active holder sessC and deletes it (resolved-holder path).
      await fronting.hardDelete('sessA');
      expect(
        await db.select(db.frontingSessions).get(),
        isEmpty,
        reason: 'holder sessC deleted via the resolved-holder path',
      );
      expect(
        await aliasCount('fronting_sessions'),
        0,
        reason: 'identity-keyed purge drops the SIBLING sessB alias too',
      );

      // Re-import with the same historical switch start.
      await fronting.applyFields(
        'sessD',
        frontingFields(memberId: 'm1', pkUuid: 'SW', startTime: start),
      );
      expect((await db.select(db.frontingSessions).get()).single.id, 'sessD');

      // Delayed sibling delete of legacy sessB must no-op (its alias is gone).
      await fronting.hardDelete('sessB');
      final survivors = await db.select(db.frontingSessions).get();
      expect(
        survivors.map((r) => r.id),
        ['sessD'],
        reason: 're-imported sessD must survive the stale sibling delete',
      );
      expect(survivors.single.isDeleted, isFalse);
    });

    test('CROSS-SWITCH: killing one switch holder for member m1 does NOT purge '
        'a DIFFERENT switch\'s redirect alias (same member, different '
        'pluralkit_uuid)', () async {
      // F23-fix3 blocker probe. One member m1 has two distinct switches SW1 and
      // SW2, each redirected onto its own holder:
      //   sessA1 -> hold1  (uuid SW1, member m1)
      //   sessA2 -> hold2  (uuid SW2, member m1)
      // Killing SW1's holder via the resolved-holder delete path must scope its
      // identity purge to SW1's uuid. The previous (uuid OR member_id) purge
      // matched the member_id arm and swept sessA2's SW2 alias too, so SW2's
      // later legitimate delete permanently no-op'd and hold2 survived. With the
      // pk_uuid-only purge, SW2's alias is untouched and its delete still kills
      // hold2.
      final fronting = entityFor('fronting_sessions');
      final start = DateTime.utc(2024, 1, 1, 8);

      // SW1: holder hold1; sessA1 redirects onto it.
      await fronting.applyFields(
        'hold1',
        frontingFields(memberId: 'm1', pkUuid: 'SW1', startTime: start),
      );
      await fronting.applyFields(
        'sessA1',
        frontingFields(memberId: 'm1', pkUuid: 'SW1', startTime: start),
      );
      // SW2: holder hold2; sessA2 redirects onto it. (Different switch start so
      // SW2's session is a distinct active row — same member, different uuid.)
      final start2 = DateTime.utc(2024, 1, 2, 8);
      await fronting.applyFields(
        'hold2',
        frontingFields(memberId: 'm1', pkUuid: 'SW2', startTime: start2),
      );
      await fronting.applyFields(
        'sessA2',
        frontingFields(memberId: 'm1', pkUuid: 'SW2', startTime: start2),
      );

      expect(
        (await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
          'fronting_sessions',
          'sessA1',
        ))?.pkUuid,
        'SW1',
      );
      expect(
        (await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
          'fronting_sessions',
          'sessA2',
        ))?.pkUuid,
        'SW2',
      );

      // Kill SW1's holder via the resolved-holder hardDelete path (delete of
      // legacy sessA1, no exact-id row -> resolves identity SW1 to hold1).
      await fronting.hardDelete('sessA1');

      // hold1 is gone; hold2 (SW2) must still be alive.
      final afterFirst = await db.select(db.frontingSessions).get();
      expect(
        afterFirst.map((r) => r.id).toSet(),
        {'hold2'},
        reason: "killing SW1's holder must not touch SW2's session",
      );
      // SW2's alias must SURVIVE — the member_id OR-arm must not have swept it.
      expect(
        await db.pkIdentitySyncAliasesDao.getByLegacyEntityId(
          'fronting_sessions',
          'sessA2',
        ),
        isNotNull,
        reason: "SW2's redirect alias must survive killing SW1's holder",
      );

      // SW2's later legitimate delete (legacy sessA2, no exact-id row) must
      // still resolve identity SW2 to hold2 and kill it.
      await fronting.hardDelete('sessA2');
      expect(
        await db.select(db.frontingSessions).get(),
        isEmpty,
        reason: "SW2's delete must still resolve and kill hold2",
      );
      expect(await aliasCount('fronting_sessions'), 0);
    });
  });
}
