import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/database/daos/custom_fields_dao.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// Subclass that overrides syncRecordDelete so tests can capture delete
/// tombstone emissions without a real Rust FFI handle.
class _RecordingRepo extends DriftCustomFieldsRepository {
  _RecordingRepo(CustomFieldsDao dao) : super(dao, null);

  final deletes = <({String table, String entityId})>[];

  @override
  Future<void> syncRecordDelete(String table, String entityId) async {
    deletes.add((table: table, entityId: entityId));
  }

  @override
  Future<void> syncRecordDeleteMulti(String table, List<String> entityIds) async {
    for (final entityId in entityIds) {
      deletes.add((table: table, entityId: entityId));
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _kEpoch = DateTime.utc(2026, 1, 1);

Future<void> _seedField(
  db.AppDatabase database, {
  required String id,
  bool isDeleted = false,
}) async {
  await database.customFieldsDao.createField(
    db.CustomFieldsCompanion.insert(
      id: id,
      name: 'Field $id',
      fieldType: 0,
      createdAt: _kEpoch,
      isDeleted: Value(isDeleted),
    ),
  );
}

Future<void> _seedValue(
  db.AppDatabase database, {
  required String id,
  required String fieldId,
  bool isDeleted = false,
}) async {
  // Use id as memberId so each (customFieldId, memberId) pair is unique,
  // satisfying the unique constraint on the custom_field_values table.
  await database.customFieldsDao.upsertValue(
    db.CustomFieldValuesCompanion.insert(
      id: id,
      customFieldId: fieldId,
      memberId: id,
      value: 'v',
      isDeleted: Value(isDeleted),
    ),
  );
}

/// Query ALL custom_fields rows without the isDeleted filter.
Future<List<db.CustomFieldRow>> _allFieldsIncludingDeleted(
  db.AppDatabase database,
) =>
    database.select(database.customFields).get();

/// Query ALL custom_field_values rows without the isDeleted filter.
Future<List<db.CustomFieldValueRow>> _allValuesIncludingDeleted(
  db.AppDatabase database,
) =>
    database.select(database.customFieldValues).get();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late db.AppDatabase database;
  late _RecordingRepo repo;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    repo = _RecordingRepo(database.customFieldsDao);
  });

  tearDown(() async {
    await database.close();
  });

  // The abstract repo type is used here so that this file fails to compile
  // until `deleteAllFields()` is declared on `CustomFieldsRepository`.
  CustomFieldsRepository abstractRef(DriftCustomFieldsRepository r) => r;

  test(
    'deleteAllFields tombstones all non-deleted fields and values',
    () async {
      await _seedField(database, id: 'f1');
      await _seedField(database, id: 'f2');
      await _seedField(database, id: 'f3');
      await _seedValue(database, id: 'v1', fieldId: 'f1');
      await _seedValue(database, id: 'v2', fieldId: 'f1');
      await _seedValue(database, id: 'v3', fieldId: 'f2');
      await _seedValue(database, id: 'v4', fieldId: 'f2');
      await _seedValue(database, id: 'v5', fieldId: 'f3');

      await abstractRef(repo).deleteAllFields();

      final allFields = await _allFieldsIncludingDeleted(database);
      expect(allFields, hasLength(3));
      expect(allFields.every((r) => r.isDeleted), isTrue);

      final allValues = await _allValuesIncludingDeleted(database);
      expect(allValues, hasLength(5));
      expect(allValues.every((r) => r.isDeleted), isTrue);
    },
  );

  test(
    'deleteAllFields emits syncRecordDelete for each non-deleted field and value ID',
    () async {
      await _seedField(database, id: 'f1');
      await _seedField(database, id: 'f2');
      await _seedField(database, id: 'f3');
      await _seedValue(database, id: 'v1', fieldId: 'f1');
      await _seedValue(database, id: 'v2', fieldId: 'f1');
      await _seedValue(database, id: 'v3', fieldId: 'f2');
      await _seedValue(database, id: 'v4', fieldId: 'f2');
      await _seedValue(database, id: 'v5', fieldId: 'f3');

      await abstractRef(repo).deleteAllFields();

      expect(repo.deletes, hasLength(8));

      // Value tombstones come before field tombstones.
      final valueDeletes = repo.deletes
          .where((d) => d.table == 'custom_field_values')
          .toList();
      final fieldDeletes = repo.deletes
          .where((d) => d.table == 'custom_fields')
          .toList();

      expect(valueDeletes, hasLength(5));
      expect(fieldDeletes, hasLength(3));

      // All value ops must appear before any field op in the full list.
      final lastValueIdx = repo.deletes.lastIndexWhere(
        (d) => d.table == 'custom_field_values',
      );
      final firstFieldIdx = repo.deletes.indexWhere(
        (d) => d.table == 'custom_fields',
      );
      expect(
        lastValueIdx < firstFieldIdx,
        isTrue,
        reason: 'value tombstones must precede all field tombstones',
      );

      expect(
        valueDeletes.map((d) => d.entityId).toSet(),
        {'v1', 'v2', 'v3', 'v4', 'v5'},
      );
      expect(
        fieldDeletes.map((d) => d.entityId).toSet(),
        {'f1', 'f2', 'f3'},
      );
    },
  );

  test(
    'deleteAllFields skips already-tombstoned rows in sync emissions',
    () async {
      // 2 active fields + 1 already-tombstoned field.
      await _seedField(database, id: 'f-active-1');
      await _seedField(database, id: 'f-active-2');
      await _seedField(database, id: 'f-dead', isDeleted: true);
      // 3 active values + 1 already-tombstoned value.
      await _seedValue(database, id: 'v-active-1', fieldId: 'f-active-1');
      await _seedValue(database, id: 'v-active-2', fieldId: 'f-active-1');
      await _seedValue(database, id: 'v-active-3', fieldId: 'f-active-2');
      await _seedValue(
        database,
        id: 'v-dead',
        fieldId: 'f-dead',
        isDeleted: true,
      );

      await abstractRef(repo).deleteAllFields();

      // Exactly 5 sync ops: 3 active values + 2 active fields (not 8).
      expect(repo.deletes, hasLength(5));

      final emittedIds = repo.deletes.map((d) => d.entityId).toSet();
      expect(emittedIds.contains('f-dead'), isFalse);
      expect(emittedIds.contains('v-dead'), isFalse);
      expect(emittedIds, containsAll(['f-active-1', 'f-active-2']));
      expect(
        emittedIds,
        containsAll(['v-active-1', 'v-active-2', 'v-active-3']),
      );
    },
  );

  test(
    'deleteAllFields is a no-op on empty data',
    () async {
      await abstractRef(repo).deleteAllFields();

      expect(repo.deletes, isEmpty);
    },
  );

  test(
    'deleteAllFields handles post-members-reset state correctly',
    () async {
      await _seedField(database, id: 'f1');
      await _seedField(database, id: 'f2');
      await _seedValue(database, id: 'v1', fieldId: 'f1');
      await _seedValue(database, id: 'v2', fieldId: 'f1');
      await _seedValue(database, id: 'v3', fieldId: 'f2');

      // Hard-delete values (simulating _resetMembers behaviour).
      await database.customStatement('DELETE FROM custom_field_values');

      await abstractRef(repo).deleteAllFields();

      final fieldDeletes = repo.deletes
          .where((d) => d.table == 'custom_fields')
          .toList();
      final valueDeletes = repo.deletes
          .where((d) => d.table == 'custom_field_values')
          .toList();

      expect(fieldDeletes, hasLength(2));
      expect(valueDeletes, isEmpty);

      expect(
        fieldDeletes.map((d) => d.entityId).toSet(),
        {'f1', 'f2'},
      );
    },
  );
}
