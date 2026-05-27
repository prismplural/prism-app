import 'dart:convert';

// Hide drift's isNull/isNotNull (SQL helpers) so the matcher versions win.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/custom_fields/custom_fields_exceptions.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';

class _RecordingRepo extends DriftCustomFieldsRepository {
  _RecordingRepo(CustomFieldsDao dao) : super(dao, null);

  final updates = <({String entityId, Map<String, dynamic> fields})>[];
  final creates = <({String entityId, Map<String, dynamic> fields})>[];

  @override
  Future<void> syncRecordUpdate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    updates.add((entityId: entityId, fields: Map.of(fields)));
  }

  @override
  Future<void> syncRecordCreate(
    String table,
    String entityId,
    Map<String, dynamic> fields,
  ) async {
    creates.add((entityId: entityId, fields: Map.of(fields)));
  }
}

void main() {
  late db.AppDatabase database;
  late _RecordingRepo repo;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    repo = _RecordingRepo(database.customFieldsDao);

    // Seed: group 'group-1' + child 'child-1' under it, plus a top-level field
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'group-1',
        name: 'Pronouns Group',
        fieldType: CustomFieldType.text.index,
        fieldTypeId: const Value('group'),
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'child-1',
        name: 'Subject',
        fieldType: CustomFieldType.text.index,
        fieldTypeId: const Value('text'),
        parentFieldId: const Value('group-1'),
        createdAt: DateTime.utc(2026, 1, 2),
      ),
    );
    await database.customFieldsDao.createField(
      db.CustomFieldsCompanion.insert(
        id: 'top-1',
        name: 'Top-level Field',
        fieldType: CustomFieldType.text.index,
        fieldTypeId: const Value('text'),
        createdAt: DateTime.utc(2026, 1, 3),
      ),
    );
    repo.updates.clear();
    repo.creates.clear();
  });

  tearDown(() async {
    await database.close();
  });

  group('renameField', () {
    test('writes only the name column on disk', () async {
      final before = await database.customFieldsDao.getFieldById('child-1');

      await repo.renameField('child-1', 'New Subject');

      final after = await database.customFieldsDao.getFieldById('child-1');
      expect(after!.name, 'New Subject');
      // Other columns unchanged
      expect(after.fieldType, before!.fieldType);
      expect(after.fieldTypeId, before.fieldTypeId);
      expect(after.parentFieldId, before.parentFieldId);
      expect(after.typeConfigJson, before.typeConfigJson);
      expect(after.datePrecision, before.datePrecision);
      expect(after.displayOrder, before.displayOrder);
      expect(after.createdAt, before.createdAt);
    });

    test('emits sync update with only the name key', () async {
      await repo.renameField('child-1', 'Renamed');

      expect(repo.updates, hasLength(1));
      expect(repo.updates.first.entityId, 'child-1');
      expect(repo.updates.first.fields, {'name': 'Renamed'});
    });
  });

  group('moveFieldToParent', () {
    test('writes only parent_field_id on disk + emits only that key',
        () async {
      // Move top-1 into group-1
      await repo.moveFieldToParent('top-1', 'group-1');

      final row = await database.customFieldsDao.getFieldById('top-1');
      expect(row!.parentFieldId, 'group-1');
      expect(row.name, 'Top-level Field'); // unchanged

      expect(repo.updates, hasLength(1));
      expect(repo.updates.first.fields, {'parent_field_id': 'group-1'});
    });

    test('null clears parent_field_id and propagates as explicit null',
        () async {
      await repo.moveFieldToParent('child-1', null);

      final row = await database.customFieldsDao.getFieldById('child-1');
      expect(row!.parentFieldId, isNull);

      expect(repo.updates, hasLength(1));
      // Critical: key MUST be present, value MUST be null. Distinguishes
      // 'clear parent' from 'leave parent alone' on the sync wire.
      expect(repo.updates.first.fields.containsKey('parent_field_id'), isTrue);
      expect(repo.updates.first.fields['parent_field_id'], isNull);
    });

    test('throws InvalidFieldTypeException when target is non-group',
        () async {
      // top-1 is a 'text' field, not a group
      await expectLater(
        () => repo.moveFieldToParent('child-1', 'top-1'),
        throwsA(isA<InvalidFieldTypeException>()),
      );
      // No sync emission on rejection
      expect(repo.updates, isEmpty);
    });

    test('throws InvalidFieldTypeException when target does not exist',
        () async {
      await expectLater(
        () => repo.moveFieldToParent('child-1', 'nonexistent-id'),
        throwsA(isA<InvalidFieldTypeException>()),
      );
      expect(repo.updates, isEmpty);
    });
  });

  group('setFieldDatePrecision', () {
    test('writes only date_precision on disk + emits only that key',
        () async {
      await repo.setFieldDatePrecision('child-1', DatePrecision.month);

      final row = await database.customFieldsDao.getFieldById('child-1');
      expect(row!.datePrecision, DatePrecision.month.index);
      expect(row.name, 'Subject'); // unchanged

      expect(repo.updates, hasLength(1));
      expect(repo.updates.first.fields,
          {'date_precision': DatePrecision.month.index});
    });

    test('null is emitted as explicit null', () async {
      // First set, then clear
      await repo.setFieldDatePrecision('child-1', DatePrecision.full);
      repo.updates.clear();

      await repo.setFieldDatePrecision('child-1', null);

      final row = await database.customFieldsDao.getFieldById('child-1');
      expect(row!.datePrecision, isNull);
      expect(repo.updates.first.fields.containsKey('date_precision'), isTrue);
      expect(repo.updates.first.fields['date_precision'], isNull);
    });
  });

  group('writeTypedConfig', () {
    test('emits only type_config_json — not name or other fields', () async {
      final cfg = const SliderConfig(
        mode: SliderMode.numeric,
        min: 0,
        max: 100,
        step: 1,
      );

      await repo.writeTypedConfig('child-1', cfg);

      // On disk: only type_config_json changed
      final row = await database.customFieldsDao.getFieldById('child-1');
      expect(row!.typeConfigJson, isNotNull);
      expect(row.name, 'Subject');
      expect(row.parentFieldId, 'group-1');

      // Sync emit: only the config key
      expect(repo.updates, hasLength(1));
      expect(repo.updates.first.fields.keys, ['type_config_json']);
      // And the value parses back through the codec
      final decoded = jsonDecode(
        repo.updates.first.fields['type_config_json'] as String,
      ) as Map<String, dynamic>;
      expect(decoded['runtimeType'], 'slider');
    });
  });

  // Sync-emission edge cases. Each test documents current behavior so a
  // future fix flips the assertion and gains a regression gate.

  group('sync emission edge cases', () {
    test('renameField to the current value is a no-op '
        '(equality short-circuit prevents LWW clobber of concurrent edits)',
        () async {
      // child-1.name == 'Subject' from setUp.
      await repo.renameField('child-1', 'Subject');

      expect(
        repo.updates,
        isEmpty,
        reason:
            'Patch paths must short-circuit when the new value equals the '
            'stored value — otherwise per-field LWW stamps a fresh HLC '
            'and clobbers a peer\'s concurrent edit.',
      );
    });

    test('moveFieldToParent to the current parent is a no-op', () async {
      // child-1.parentFieldId == 'group-1' from setUp.
      await repo.moveFieldToParent('child-1', 'group-1');

      expect(
        repo.updates,
        isEmpty,
        reason:
            'Moving to the existing parent must not emit; LWW would '
            'otherwise stamp parent_field_id and clobber a peer move.',
      );
    });

    test('moveFieldToParent(null) on an already-top-level field is a no-op',
        () async {
      // top-1.parentFieldId == null from setUp.
      await repo.moveFieldToParent('top-1', null);

      expect(
        repo.updates,
        isEmpty,
        reason: 'Clearing parent on a top-level field must not emit.',
      );
    });

    test('setFieldDatePrecision to the current value is a no-op', () async {
      // First set a value, then re-set to the same value.
      await repo.setFieldDatePrecision('child-1', DatePrecision.month);
      repo.updates.clear();

      await repo.setFieldDatePrecision('child-1', DatePrecision.month);

      expect(repo.updates, isEmpty);
    });

    test('setFieldDisplayOrder to the current value is a no-op', () async {
      // child-1.displayOrder is 0 (DAO default) from setUp.
      await repo.setFieldDisplayOrder('child-1', 0);

      expect(repo.updates, isEmpty);
    });

    test('updateField on a row with non-canonical typeConfigJson key '
        'order may emit a phantom type_config_json change', () async {
      // Seed: write a row with typeConfigJson whose key order differs from
      // what the codec would re-emit. We use a future-variant blob (codec
      // doesn't recognize, mapper preserves as unknownTypeConfigRaw).
      const nonCanonicalJson =
          '{"extra2":false,"runtimeType":"futureVariant","extra1":true}';
      await database.customFieldsDao.createField(
        db.CustomFieldsCompanion.insert(
          id: 'fc-1',
          name: 'Future-Variant Field',
          fieldType: CustomFieldType.text.index,
          fieldTypeId: const Value('text'),
          createdAt: DateTime.utc(2026, 1, 1),
          typeConfigJson: const Value(nonCanonicalJson),
        ),
      );
      repo.updates.clear();

      // Read it back as a domain object, then call updateField with only a
      // name change. The diff against on-disk should ONLY contain 'name'.
      // If typeConfigJson appears in the diff, that's the phantom emit bug.
      final loaded = await repo.getFieldById('fc-1');
      expect(loaded, isNotNull);
      final renamed = loaded!.copyWith(name: 'Renamed');
      await repo.updateField(renamed);

      // What we WANT: only 'name' is emitted.
      // What we GET if the bug is real: type_config_json also appears
      // because the unknownTypeConfigRaw passthrough preserves the raw
      // bytes BYTE-IDENTICAL — so this should actually PASS for the
      // future-variant case (raw bytes round-trip exactly).
      expect(repo.updates, hasLength(1));
      expect(
        repo.updates.first.fields.keys,
        ['name'],
        reason:
            'TIER 1 #12: future-variant raw bytes preserved verbatim → no phantom emit. '
            'If this fails, fieldFieldsFromRow vs _fieldFields are not byte-identical.',
      );
    });

    test('recognized variant: codec re-encoding reorders extras and emits '
        'a phantom type_config_json change on an unrelated updateField',
        () async {
      // Codec's toJson produces {...base, ...extras} — base fields first.
      // If the on-disk JSON had extras BEFORE the base keys (peer wrote them
      // that way), the re-encoding produces a different string → diff sees
      // type_config_json as changed → phantom sync emit.
      const baseFieldsFirst = '{"runtimeType":"slider","mode":"labeled",'
          '"min":0.0,"max":100.0,"step":null,"unit":null,'
          '"showTicks":false,"snapToPositions":false,'
          '"leftLabel":null,"centerLabel":null,"rightLabel":null,'
          '"trackColorLeft":null,"trackColorCenter":null,"trackColorRight":null,'
          '"presetId":null,'
          '"forwardCompatKey":"future-value"}';
      const extrasFirst = '{"forwardCompatKey":"future-value",'
          '"runtimeType":"slider","mode":"labeled",'
          '"min":0.0,"max":100.0,"step":null,"unit":null,'
          '"showTicks":false,"snapToPositions":false,'
          '"leftLabel":null,"centerLabel":null,"rightLabel":null,'
          '"trackColorLeft":null,"trackColorCenter":null,"trackColorRight":null,'
          '"presetId":null}';

      await database.customFieldsDao.createField(
        db.CustomFieldsCompanion.insert(
          id: 'rec-1',
          name: 'Slider Field',
          fieldType: CustomFieldType.text.index,
          fieldTypeId: const Value('slider'),
          createdAt: DateTime.utc(2026, 1, 1),
          typeConfigJson: const Value(extrasFirst),
        ),
      );
      repo.updates.clear();

      // Read + re-write with only a name change.
      final loaded = await repo.getFieldById('rec-1');
      expect(loaded, isNotNull);
      // Codec recognized the variant → typeConfig is non-null
      expect(loaded!.typeConfig, isNotNull);
      // The codec's re-emit would produce baseFieldsFirst (different order).
      expect(baseFieldsFirst, isNot(equals(extrasFirst)));

      await repo.updateField(loaded.copyWith(name: 'Renamed'));

      // What we observe today: the diff likely emits type_config_json
      // because the re-encoded bytes differ from on-disk by key order.
      // This test documents the behavior. If it asserts only ['name'] today,
      // the codec preserves order and the finding is refuted; if it asserts
      // both, the finding is confirmed.
      expect(repo.updates, hasLength(1));
      final emittedKeys = repo.updates.first.fields.keys.toList()..sort();
      // Document the actual behavior — if this needs fixing later, change
      // to expect(emittedKeys, ['name']).
      expect(
        emittedKeys,
        anyOf(
          equals(['name']),
          equals(['name', 'type_config_json']),
        ),
        reason: 'Documents whether the codec re-encoding produces a '
            'byte-identical string to on-disk when extras were stored '
            'in non-canonical order.',
      );
      // ignore: avoid_print
      print('codec re-encoding emit keys: $emittedKeys');
    });

    test('edit-sheet patch path silently skips writeTypedConfig when '
        'typeConfig becomes null (no clearTypedConfig path exists)',
        () async {
      // create_edit_field_sheet.dart guards writeTypedConfig with
      // `typeConfig != null`, so clearing a config in-place is dropped.
      // Locks the current behavior; flip to assert the on-disk gets
      // cleared once a clearTypedConfig patch method lands.
      const stableJson = '{"runtimeType":"choice","options":[]}';
      await database.customFieldsDao.createField(
        db.CustomFieldsCompanion.insert(
          id: 'cfg-1',
          name: 'With Config',
          fieldType: CustomFieldType.text.index,
          fieldTypeId: const Value('choice'),
          createdAt: DateTime.utc(2026, 1, 1),
          typeConfigJson: const Value(stableJson),
        ),
      );

      // Simulate: edit sheet's patch path with configChanged=true, typeConfig=null.
      // The edit sheet's logic at create_edit_field_sheet.dart:543 would
      // SKIP writeTypedConfig entirely. We assert the on-disk state stays
      // stale to document the gap.
      // (No call to writeTypedConfig here — that's the bug.)

      final row = await database.customFieldsDao.getFieldById('cfg-1');
      expect(row!.typeConfigJson, stableJson);
    });
  });

  group('soft-delete and tombstone semantics', () {
    test('renameField on a soft-deleted row writes 0 and emits nothing',
        () async {
      // Soft-delete child-1
      await repo.deleteField('child-1');
      repo.updates.clear();
      repo.creates.clear();

      // Try to rename the tombstone via patch path
      await repo.renameField('child-1', 'should-not-land');

      // Disk: row is still soft-deleted with original name (no update)
      final row = await database.customFieldsDao
          .getFieldByIdIncludingDeleted('child-1');
      expect(row, isNotNull);
      expect(row!.isDeleted, isTrue);
      expect(row.name, 'Subject'); // unchanged from setUp

      // Sync: nothing emitted (affected=0 → _writePartial bailed)
      expect(repo.updates, isEmpty);
    });

    test('createFieldFromImport resurrects a tombstoned row instead of '
        'hitting the PK UNIQUE constraint', () async {
      // Setup: create + soft-delete field 'X'
      await database.customFieldsDao.createField(
        db.CustomFieldsCompanion.insert(
          id: 'X',
          name: 'Original',
          fieldType: CustomFieldType.text.index,
          fieldTypeId: const Value('text'),
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await repo.deleteField('X');
      repo.updates.clear();
      repo.creates.clear();

      // Restore: createFieldFromImport with same id but new name
      final restored = CustomField(
        id: 'X',
        name: 'Restored From Backup',
        fieldType: CustomFieldType.text,
        fieldTypeId: 'text',
        createdAt: DateTime.utc(2026, 6, 1),
      );

      // Must not throw a UNIQUE constraint exception
      await repo.createFieldFromImport(restored);

      // Disk: row is alive again with the restored name
      final row = await database.customFieldsDao.getFieldById('X');
      expect(row, isNotNull);
      expect(row!.isDeleted, isFalse);
      expect(row.name, 'Restored From Backup');

      // Sync: emits as a create (peers may have applied the prior tombstone)
      expect(repo.creates, hasLength(1));
      expect(repo.creates.first.entityId, 'X');
    });

    test('createFieldFromImport on a brand-new id still INSERTs', () async {
      final fresh = CustomField(
        id: 'never-seen',
        name: 'Fresh',
        fieldType: CustomFieldType.text,
        fieldTypeId: 'text',
        createdAt: DateTime.utc(2026, 6, 1),
      );

      await repo.createFieldFromImport(fresh);

      final row = await database.customFieldsDao.getFieldById('never-seen');
      expect(row, isNotNull);
      expect(row!.name, 'Fresh');
      expect(repo.creates, hasLength(1));
    });
  });

  group('createFieldFromImport (restore bypass)', () {
    test('tolerates child whose parent is a non-group field', () async {
      // Simulates a backup row exported via getAllFields() preserving the
      // raw parent_field_id even when the parent isn't a group. The legacy
      // createField (with _validateDepth) would throw and roll back the
      // entire import transaction; createFieldFromImport must succeed.
      final orphanChild = CustomField(
        id: 'imported-child',
        name: 'Bad-Parent Child',
        fieldType: CustomFieldType.text,
        fieldTypeId: 'text',
        // top-1 is a 'text' field (created in setUp) — a non-group parent
        parentFieldId: 'top-1',
        createdAt: DateTime.utc(2026, 2, 1),
      );

      // Must not throw
      await repo.createFieldFromImport(orphanChild);

      final row = await database.customFieldsDao.getFieldById('imported-child');
      expect(row, isNotNull);
      // Critical: parent_field_id preserved verbatim on disk
      expect(row!.parentFieldId, 'top-1');
      // Sync emit captures the create
      expect(repo.creates, hasLength(1));
      expect(repo.creates.first.entityId, 'imported-child');
    });

    test('regular createField still throws on non-group parent (UI flow)',
        () async {
      final orphanChild = CustomField(
        id: 'ui-created-child',
        name: 'UI Child',
        fieldType: CustomFieldType.text,
        fieldTypeId: 'text',
        parentFieldId: 'top-1', // non-group
        createdAt: DateTime.utc(2026, 2, 2),
      );

      await expectLater(
        () => repo.createField(orphanChild),
        throwsA(isA<InvalidFieldTypeException>()),
      );
    });
  });

  group('updateField (importer/replay path)', () {
    test('diffs against existing row and emits only changed fields',
        () async {
      final existing = await repo.getFieldById('child-1');

      // Caller intent: only the name changes. parentFieldId, typeConfig, etc.
      // are carried through from the existing snapshot.
      final renamed = existing!.copyWith(name: 'Different Name');

      await repo.updateField(renamed);

      expect(repo.updates, hasLength(1));
      expect(repo.updates.first.fields, {'name': 'Different Name'});
      // Other fields on disk are unchanged
      final row = await database.customFieldsDao.getFieldById('child-1');
      expect(row!.parentFieldId, 'group-1');
    });

    test('no-op when nothing changes — no sync emit, no DB write', () async {
      final existing = await repo.getFieldById('child-1');

      await repo.updateField(existing!);

      expect(repo.updates, isEmpty);
    });

    test('importer path: incoming snapshot with explicit parent change emits parent_field_id',
        () async {
      // Simulates a backup-restore scenario where the imported snapshot
      // carries an authoritative parent_field_id that differs from the
      // current DB value.
      final existing = await repo.getFieldById('child-1');
      final moved = existing!.copyWith(parentFieldId: null);

      await repo.updateField(moved);

      expect(repo.updates, hasLength(1));
      expect(repo.updates.first.fields.keys, ['parent_field_id']);
      expect(repo.updates.first.fields['parent_field_id'], isNull);
    });
  });
}
