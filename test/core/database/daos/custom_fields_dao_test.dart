import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<void> insertField(String id, {bool isDeleted = false}) =>
      db.customFieldsDao.createField(
        CustomFieldsCompanion.insert(
          id: id,
          name: 'Field $id',
          fieldType: 0,
          createdAt: DateTime(2024),
          isDeleted: Value(isDeleted),
        ),
      );

  Future<void> insertValue(String id, {bool isDeleted = false}) =>
      db.customFieldsDao.upsertValue(
        CustomFieldValuesCompanion.insert(
          id: id,
          customFieldId: 'field-1',
          memberId: 'member-$id', // unique per value to avoid (field,member) constraint
          value: 'v',
          isDeleted: Value(isDeleted),
        ),
      );

  // ── getNonDeletedFieldIds ────────────────────────────────────────────────────

  group('getNonDeletedFieldIds', () {
    test('returns only non-tombstoned field IDs', () async {
      await insertField('f-1');
      await insertField('f-2');
      await insertField('f-3');
      await insertField('f-dead', isDeleted: true);

      final ids = await db.customFieldsDao.getNonDeletedFieldIds();

      expect(ids, hasLength(3));
      expect(ids, containsAll(['f-1', 'f-2', 'f-3']));
      expect(ids, isNot(contains('f-dead')));
    });
  });

  // ── getNonDeletedValueIds ────────────────────────────────────────────────────

  group('getNonDeletedValueIds', () {
    test('returns only non-tombstoned value IDs', () async {
      await insertField('field-1'); // FK anchor
      await insertValue('v-1');
      await insertValue('v-2');
      await insertValue('v-dead', isDeleted: true);

      final ids = await db.customFieldsDao.getNonDeletedValueIds();

      expect(ids, hasLength(2));
      expect(ids, containsAll(['v-1', 'v-2']));
      expect(ids, isNot(contains('v-dead')));
    });
  });

  // ── upsertValue burned-id mint ───────────────────────────────────────────────

  group('upsertValue', () {
    setUp(() => insertField('field-1'));

    CustomFieldValuesCompanion companion(String id, String value) =>
        CustomFieldValuesCompanion.insert(
          id: id,
          customFieldId: 'field-1',
          memberId: 'member-1',
          value: value,
        );

    test('first-ever fill keeps the given (deterministic) id', () async {
      final written = await db.customFieldsDao.upsertValue(
        companion('det-1', 'first'),
      );
      expect(written, 'det-1');
    });

    test('refill after a tombstone at the id mints a fresh row, never reviving '
        'the burned id', () async {
      await db.customFieldsDao.upsertValue(companion('det-1', 'first'));
      await db.customFieldsDao.deleteValue('det-1');

      final written = await db.customFieldsDao.upsertValue(
        companion('det-1', 'refill'),
        mintFreshId: () => 'fresh-1',
      );

      expect(written, 'fresh-1');
      final active = await db.customFieldsDao.getValueForField(
        'field-1',
        'member-1',
      );
      expect(active!.id, 'fresh-1');
      expect(active.value, 'refill');
      // The burned id stays tombstoned (not resurrected).
      final burned = await (db.select(
        db.customFieldValues,
      )..where((v) => v.id.equals('det-1'))).getSingle();
      expect(burned.isDeleted, isTrue);
    });

    test('writing to a live row at the id updates it in place', () async {
      await db.customFieldsDao.upsertValue(companion('det-1', 'first'));
      final written = await db.customFieldsDao.upsertValue(
        companion('det-1', 'edited'),
      );
      expect(written, 'det-1');
      final active = await db.customFieldsDao.getValueForField(
        'field-1',
        'member-1',
      );
      expect(active!.value, 'edited');
    });

    test('an active logical row wins over a mismatched incoming id (never '
        'writes the derived/burned id)', () async {
      // Active row under a minted id; caller passes the deterministic id.
      await db.customFieldsDao.upsertValue(companion('minted-1', 'live'));
      final written = await db.customFieldsDao.upsertValue(
        companion('det-1', 'edited'),
      );
      expect(written, 'minted-1');
      final active = await db.customFieldsDao.getValueForField(
        'field-1',
        'member-1',
      );
      expect(active!.id, 'minted-1');
      expect(active.value, 'edited');
      // The deterministic id was never inserted.
      final det = await (db.select(
        db.customFieldValues,
      )..where((v) => v.id.equals('det-1'))).getSingleOrNull();
      expect(det, isNull);
    });
  });

  // ── reconcileValuesFromImport ────────────────────────────────────────────────

  group('reconcileValuesFromImport', () {
    setUp(() => insertField('field-1'));

    CustomFieldValuesCompanion companion(
      String id,
      String memberId,
      String value,
    ) => CustomFieldValuesCompanion.insert(
      id: id,
      customFieldId: 'field-1',
      memberId: memberId,
      value: value,
    );

    test('adopts the live row id, inserts unseen ids, and mints over a '
        'burned id', () async {
      // member-a: active row under a minted id (import carries another id).
      await db.customFieldsDao.upsertValue(
        companion('minted-a', 'member-a', 'live'),
      );
      // member-b: tombstone at the exact id the import will target.
      await db.customFieldsDao.upsertValue(
        companion('det-b', 'member-b', 'old'),
      );
      await db.customFieldsDao.deleteValue('det-b');

      final written = await db.customFieldsDao.reconcileValuesFromImport([
        companion('det-a', 'member-a', 'imported-a'),
        companion('det-b', 'member-b', 'imported-b'),
        companion('det-c', 'member-c', 'imported-c'),
      ], mintFreshId: () => 'fresh-b');

      expect(written, ['minted-a', 'fresh-b', 'det-c']);
      final a = await db.customFieldsDao.getValueForField(
        'field-1',
        'member-a',
      );
      expect(a!.id, 'minted-a');
      expect(a.value, 'imported-a');
      final b = await db.customFieldsDao.getValueForField(
        'field-1',
        'member-b',
      );
      expect(b!.id, 'fresh-b');
      expect(b.value, 'imported-b');
      final burned = await (db.select(
        db.customFieldValues,
      )..where((v) => v.id.equals('det-b'))).getSingle();
      expect(burned.isDeleted, isTrue);
      final c = await db.customFieldsDao.getValueForField(
        'field-1',
        'member-c',
      );
      expect(c!.id, 'det-c');
    });

    test('resolution stays correct across the 500-row lookup chunk boundary',
        () async {
      // Pre-seed one adopt case and one burned id, both in the third chunk.
      await db.customFieldsDao.upsertValue(
        CustomFieldValuesCompanion.insert(
          id: 'zz-active-0700',
          customFieldId: 'field-1',
          memberId: 'member-0700',
          value: 'live',
        ),
      );
      await db.customFieldsDao.upsertValue(
        CustomFieldValuesCompanion.insert(
          id: 'target-0800',
          customFieldId: 'field-1',
          memberId: 'member-0800',
          value: 'old',
        ),
      );
      await db.customFieldsDao.deleteValue('target-0800');

      final rows = [
        for (var i = 0; i < 1100; i++)
          CustomFieldValuesCompanion.insert(
            id: 'target-${i.toString().padLeft(4, '0')}',
            customFieldId: 'field-1',
            memberId: 'member-${i.toString().padLeft(4, '0')}',
            value: 'v$i',
          ),
      ];
      final written = await db.customFieldsDao.reconcileValuesFromImport(
        rows,
        mintFreshId: () => 'fresh-0800',
      );

      expect(written.length, 1100);
      expect(written[0], 'target-0000');
      expect(written[499], 'target-0499');
      expect(written[500], 'target-0500');
      expect(written[700], 'zz-active-0700');
      expect(written[800], 'fresh-0800');
      expect(written[1099], 'target-1099');
      final active = await (db.select(db.customFieldValues)
            ..where((v) => v.isDeleted.equals(false)))
          .get();
      expect(active.length, 1100);
      expect(
        active.singleWhere((r) => r.memberId == 'member-0700').value,
        'v700',
      );
      expect(
        active.singleWhere((r) => r.memberId == 'member-0800').id,
        'fresh-0800',
      );
    });

    test('duplicate (field, member) inputs over a burned id collapse onto one '
        'minted row, last value wins', () async {
      await db.customFieldsDao.upsertValue(
        companion('det-d', 'member-d', 'old'),
      );
      await db.customFieldsDao.deleteValue('det-d');

      var mints = 0;
      final written = await db.customFieldsDao.reconcileValuesFromImport([
        companion('det-d', 'member-d', 'first'),
        companion('det-d', 'member-d', 'second'),
      ], mintFreshId: () => 'fresh-${++mints}');

      expect(written, ['fresh-1', 'fresh-1']);
      final d = await db.customFieldsDao.getValueForField(
        'field-1',
        'member-d',
      );
      expect(d!.id, 'fresh-1');
      expect(d.value, 'second');
    });
  });

  // ── softDeleteAllCustomFieldData ─────────────────────────────────────────────

  group('softDeleteAllCustomFieldData', () {
    test('tombstones every non-deleted row', () async {
      await insertField('f-active-1');
      await insertField('f-active-2');
      await insertField('f-already-dead', isDeleted: true);
      await insertField('field-1'); // FK anchor for values
      await insertValue('v-active-1');
      await insertValue('v-active-2');
      await insertValue('v-already-dead', isDeleted: true);

      final result = await db.customFieldsDao.softDeleteAllCustomFieldData();

      // Returned IDs match the rows that were active before the call
      expect(result.fieldIds.toSet(), equals({'f-active-1', 'f-active-2', 'field-1'}));
      expect(result.valueIds.toSet(), equals({'v-active-1', 'v-active-2'}));

      // Query ALL rows including tombstones
      final allFields = await (db.select(db.customFields)).get();
      final allValues = await (db.select(db.customFieldValues)).get();

      expect(allFields, isNotEmpty);
      expect(allValues, isNotEmpty);
      for (final row in allFields) {
        expect(row.isDeleted, isTrue,
            reason: 'field ${row.id} should be tombstoned');
      }
      for (final row in allValues) {
        expect(row.isDeleted, isTrue,
            reason: 'value ${row.id} should be tombstoned');
      }
    });

    test('is idempotent', () async {
      await insertField('f-1');
      await insertField('f-2');
      await insertField('field-1'); // FK anchor for values
      await insertValue('v-1');
      await insertValue('v-2');

      final first = await db.customFieldsDao.softDeleteAllCustomFieldData();
      // First call captures all active IDs
      expect(first.fieldIds, isNotEmpty);
      expect(first.valueIds, isNotEmpty);

      final second = await db.customFieldsDao.softDeleteAllCustomFieldData(); // second call
      // Second call finds nothing active — empty lists
      expect(second.fieldIds.isEmpty, isTrue);
      expect(second.valueIds.isEmpty, isTrue);

      final allFields = await (db.select(db.customFields)).get();
      final allValues = await (db.select(db.customFieldValues)).get();

      // Row counts unchanged between calls
      expect(allFields, hasLength(3));
      expect(allValues, hasLength(2));

      // All rows still tombstoned
      for (final row in allFields) {
        expect(row.isDeleted, isTrue);
      }
      for (final row in allValues) {
        expect(row.isDeleted, isTrue);
      }
    });
  });
}
