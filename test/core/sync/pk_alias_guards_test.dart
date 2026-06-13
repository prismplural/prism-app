import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/pk_alias_guards.dart';
import 'package:prism_plurality/features/pluralkit/services/pk_groups_importer.dart';

/// Truth table for the single shared alias guard [isForbiddenAliasTarget].
///
/// It is the one predicate every alias recorder, alias-delete emitter, and the
/// migration purge consult before aliasing or tombstoning a legacy entity id.
/// Forbidden iff the id is the deterministic self-id form OR matches any active
/// local row in the table.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('isForbiddenAliasTarget', () {
    test('TRUE for the deterministic self-id form (pk-group-<uuid>)', () async {
      const pkUuid = 'uuid-self-form';
      final selfId = PkGroupsImporter.deriveGroupId(pkUuid);
      expect(selfId, 'pk-group-$pkUuid');

      // No row needs to exist: the self-id form is forbidden by construction,
      // because it IS every importing device's own local row id.
      expect(
        await isForbiddenAliasTarget(db, 'member_groups', selfId, pkUuid),
        isTrue,
      );
    });

    test('TRUE when the legacy id matches an active local row', () async {
      const activeId = 'active-loser-row';
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: activeId,
              name: 'Active',
              createdAt: DateTime.utc(2026, 5, 1),
            ),
          );

      // pkUuid intentionally does NOT derive to activeId — the active-row check
      // alone carries the guard.
      expect(
        await isForbiddenAliasTarget(
          db,
          'member_groups',
          activeId,
          'unrelated-uuid',
        ),
        isTrue,
      );
    });

    test('TRUE for a row\'s own id (members) when active', () async {
      const ownId = 'member-own-id';
      await db
          .into(db.members)
          .insert(
            MembersCompanion.insert(
              id: ownId,
              name: 'Self',
              createdAt: DateTime.utc(2026, 5, 1),
            ),
          );

      // members have no deterministic self-id form, so pkUuid is null/empty —
      // the active-row match supplies the guard.
      expect(
        await isForbiddenAliasTarget(db, 'members', ownId, null),
        isTrue,
      );
    });

    test('FALSE for a legit loser alias (random id, not active locally)',
        () async {
      // A genuine loser alias: a random row id that is NOT the self-id form and
      // does NOT exist as an active local row — exactly what the emitters MUST
      // still fan a tombstone out to.
      const loserId = 'random-loser-row-id';
      expect(
        await isForbiddenAliasTarget(
          db,
          'member_groups',
          loserId,
          'uuid-some-group',
        ),
        isFalse,
      );
    });

    test('FALSE when the only matching row is soft-deleted', () async {
      const tombstonedId = 'tombstoned-row';
      await db
          .into(db.memberGroups)
          .insert(
            MemberGroupsCompanion.insert(
              id: tombstonedId,
              name: 'Gone',
              createdAt: DateTime.utc(2026, 5, 1),
              isDeleted: const Value(true),
            ),
          );

      // A tombstoned row is not active, so its id is a legitimate alias target.
      expect(
        await isForbiddenAliasTarget(
          db,
          'member_groups',
          tombstonedId,
          'uuid-some-group',
        ),
        isFalse,
      );
    });

    test('self-id-form check is a no-op when pkUuid is null/empty', () async {
      // With no uuid there is no deterministic self-id form; a hyphen-form id
      // that happens to look like a group self-id but is not an active row is
      // still allowed.
      expect(
        await isForbiddenAliasTarget(
          db,
          'member_groups',
          'pk-group-uuid-x',
          null,
        ),
        isFalse,
      );
      expect(
        await isForbiddenAliasTarget(
          db,
          'member_groups',
          'pk-group-uuid-x',
          '',
        ),
        isFalse,
      );
    });

    test('active-row match resolves against the named table only', () async {
      // An id active in members must NOT be reported forbidden for
      // fronting_sessions (the guard is table-scoped).
      const sharedId = 'shared-id';
      await db
          .into(db.members)
          .insert(
            MembersCompanion.insert(
              id: sharedId,
              name: 'Member',
              createdAt: DateTime.utc(2026, 5, 1),
            ),
          );

      expect(
        await isForbiddenAliasTarget(db, 'members', sharedId, null),
        isTrue,
      );
      expect(
        await isForbiddenAliasTarget(db, 'fronting_sessions', sharedId, null),
        isFalse,
      );
    });
  });
}
