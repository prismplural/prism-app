// Real-SQL contract for the custom_field_values apply path. Every case here
// runs the actual UPDATE/INSERT statements against a real AppDatabase whose
// partial unique index `(custom_field_id, member_id) WHERE is_deleted = 0`
// is present (created in onCreate). No interceptor stands in for the write —
// the SQLite engine enforces the index, so a design that would produce two
// active rows or collide on the primary key surfaces as a real exception.
//
// Covered:
//  - adoption in both directions (incoming minted id wins / loses vs the
//    active row) with the total order every device computes identically;
//  - minted id beats the deterministic id;
//  - a tombstone op touches the EXACT incoming id only (a stale burned-id
//    tombstone does NOT kill the active minted row);
//  - revive-in-place when a tombstoned row sits at the incoming id;
//  - dead-row-at-X PK-collision adoption (a dead row already occupies the
//    winning id and must be cleared first);
//  - the payload that used to hit SQLITE_CONSTRAINT_UNIQUE now applies cleanly,
//    leaving exactly one active row with the incoming content.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync_drift/prism_sync_drift.dart';

import 'package:prism_plurality/core/constants/custom_field_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

void main() {
  const fieldId = 'field-1';
  const memberId = 'member-1';
  final deterministicId = deriveCustomFieldValueId(
    customFieldId: fieldId,
    memberId: memberId,
  );

  late AppDatabase db;
  late DriftSyncEntity entity;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Force beforeOpen (which creates the partial unique index) to run.
    await db.customStatement('SELECT 1');
    entity = buildSyncAdapterWithCompletion(
      db,
    ).adapter.entities.singleWhere((e) => e.tableName == 'custom_field_values');
  });

  tearDown(() => db.close());

  Future<void> seed(String id, String value, {required bool deleted}) => db
      .into(db.customFieldValues)
      .insert(
        CustomFieldValuesCompanion.insert(
          id: id,
          customFieldId: fieldId,
          memberId: memberId,
          value: value,
          isDeleted: Value(deleted),
        ),
      );

  Future<void> applyLive(String id, String value) => entity.applyFields(id, {
    'custom_field_id': fieldId,
    'member_id': memberId,
    'value': value,
    'is_deleted': false,
  });

  Future<void> applyTombstone(String id, String value) =>
      entity.applyFields(id, {
        'custom_field_id': fieldId,
        'member_id': memberId,
        'value': value,
        'is_deleted': true,
      });

  Future<List<CustomFieldValueRow>> activeRows() => (db.select(
    db.customFieldValues,
  )..where((t) => t.isDeleted.equals(false))).get();

  Future<CustomFieldValueRow?> rowAt(String id) => (db.select(
    db.customFieldValues,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  test(
    'incoming minted id WINS over the active deterministic row (adoption)',
    () async {
      await seed(deterministicId, 'old', deleted: false);

      await applyLive('minted-z', 'incoming');

      // Deterministic id never beats a minted id: the row is re-homed onto the
      // minted id in a single statement — exactly one active row, no violation.
      final active = await activeRows();
      expect(active, hasLength(1));
      expect(active.single.id, 'minted-z');
      expect(active.single.value, 'incoming');
      // No orphan left at the old deterministic id.
      expect(await rowAt(deterministicId), isNull);
    },
  );

  test(
    'incoming minted id LOSES to a higher active minted row (op dropped)',
    () async {
      await seed('minted-z', 'live', deleted: false);

      // Incoming minted id is lexicographically lower → it loses; drop the op.
      await applyLive('minted-a', 'incoming');

      final active = await activeRows();
      expect(active, hasLength(1));
      expect(active.single.id, 'minted-z');
      expect(active.single.value, 'live'); // unchanged
      expect(await rowAt('minted-a'), isNull); // loser never materialized
    },
  );

  test(
    'higher incoming minted id WINS over a lower active minted row',
    () async {
      await seed('minted-a', 'live', deleted: false);

      await applyLive('minted-z', 'incoming');

      final active = await activeRows();
      expect(active, hasLength(1));
      expect(active.single.id, 'minted-z');
      expect(active.single.value, 'incoming');
      expect(await rowAt('minted-a'), isNull);
    },
  );

  test('deterministic id LOSES to an active minted row (op dropped)', () async {
    await seed('minted-a', 'live', deleted: false);

    // The deterministic id never beats a minted id, even a lexically lower one.
    await applyLive(deterministicId, 'incoming');

    final active = await activeRows();
    expect(active, hasLength(1));
    expect(active.single.id, 'minted-a');
    expect(active.single.value, 'live');
    expect(await rowAt(deterministicId), isNull);
  });

  test(
    'stale tombstone for the burned deterministic id does NOT kill the active '
    'minted row (tombstone is exact-id-only)',
    () async {
      await seed(deterministicId, 'old', deleted: true);
      await seed('minted-z', 'survivor', deleted: false);

      // A late tombstone re-addressing the burned id must touch only that dead
      // id — never redirect through (field, member) onto the live minted row.
      await applyTombstone(deterministicId, 'old');

      final active = await activeRows();
      expect(active, hasLength(1));
      expect(active.single.id, 'minted-z');
      expect(active.single.value, 'survivor');
      // The burned id stays tombstoned; it was never revived.
      expect((await rowAt(deterministicId))!.isDeleted, isTrue);
    },
  );

  test('tombstone for a live exact id soft-deletes it in place', () async {
    await seed('minted-z', 'live', deleted: false);

    await applyTombstone('minted-z', 'live');

    expect(await activeRows(), isEmpty);
    expect((await rowAt('minted-z'))!.isDeleted, isTrue);
  });

  test(
    'live op revives a tombstoned row IN PLACE at the incoming id (case 2)',
    () async {
      await seed('minted-z', 'old', deleted: true);

      // No active row for (field, member); a tombstoned row sits at the id.
      // Delivery means the engine holds it live → revive in place.
      await applyLive('minted-z', 'refilled');

      final active = await activeRows();
      expect(active, hasLength(1));
      expect(active.single.id, 'minted-z');
      expect(active.single.value, 'refilled');
    },
  );

  test('adoption hard-deletes a dead row already at the winning id', () async {
    // Active row under a low minted id; a DEAD row already occupies the higher
    // incoming id. Adoption must clear the dead row before re-homing, or the
    // UPDATE would collide on the primary key.
    await seed('minted-a', 'live', deleted: false);
    await seed('minted-z', 'dead', deleted: true);

    await applyLive('minted-z', 'incoming');

    final active = await activeRows();
    expect(active, hasLength(1));
    expect(active.single.id, 'minted-z');
    expect(active.single.value, 'incoming');
    // Exactly one row lives at the winning id (the dead one was replaced).
    final all = await (db.select(
      db.customFieldValues,
    )..where((t) => t.id.equals('minted-z'))).get();
    expect(all, hasLength(1));
    expect(all.single.isDeleted, isFalse);
    // The loser's old id is gone.
    expect(await rowAt('minted-a'), isNull);
  });

  test(
    'the previously-throwing payload applies cleanly with no constraint error',
    () async {
      // Exact scenario the auditor proved threw SQLITE_CONSTRAINT_UNIQUE under
      // the old reordered two-write branch: a tombstone at the deterministic id
      // plus an active minted row, incoming op addressing the deterministic id.
      await seed(deterministicId, 'old', deleted: true);
      await seed('minted-1', 'survivor', deleted: false);

      // Incoming deterministic id loses the adoption race (never beats a minted
      // id) → op dropped, no write, no constraint failure.
      await applyLive(deterministicId, 'incoming');

      final active = await activeRows();
      expect(active, hasLength(1));
      expect(active.single.id, 'minted-1');
      expect(active.single.value, 'survivor');
      expect((await rowAt(deterministicId))!.isDeleted, isTrue);
    },
  );

  test(
    'higher incoming minted id adopts a lower active minted row cleanly',
    () async {
      // Guards the "X != D" clause of the total order: two minted ids compare
      // lexically; the incoming higher one wins and adopts with the real index
      // in place (no constraint error).
      await seed('minted-m', 'live', deleted: false);

      await applyLive('minted-n', 'incoming');

      final active = await activeRows();
      expect(active, hasLength(1));
      expect(active.single.id, 'minted-n');
      expect(active.single.value, 'incoming');
    },
  );
}
