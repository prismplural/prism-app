// Correctness contract for `commitValueBatch`: one durable transaction with
// sync emissions suppressed during the txn and replayed only post-commit, and
// the caller's per-field partial-failure semantics preserved.
//
// NOTE: this uses the REAL `DriftCustomFieldsRepository` (syncHandle null), not
// the `_SilentRepo` subclass other tests use — `_SilentRepo` overrides
// `syncRecord*` to no-ops, which would bypass the suppress/capture machinery
// the batch path depends on. Emissions are observed through the test-only
// capture sink instead, which short-circuits before the FFI (no Rust handle
// needed). The sink only fires when suppression is OFF, so anything it records
// was necessarily replayed *after* the batch's durable commit.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/custom_fields/custom_fields_exceptions.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_editor_scope.dart';

/// Test double for a single staged editor. Mirrors what a real per-field
/// editor's `commitPendingValue` does (write via the repo, or fail), so the
/// REAL [CustomFieldsEditorController.commit] partial-failure loop runs against
/// the REAL [DriftCustomFieldsRepository.commitValueBatch]. Only the leaf
/// editor-state is a double — everything below it is production code.
class _StubFieldState implements PendingFieldEditState {
  _StubFieldState(this.fieldId, this._commit);

  @override
  final String fieldId;
  final Future<void> Function() _commit;

  @override
  String get fieldDisplayName => 'Field $fieldId';

  @override
  Future<void> commitPendingValue() => _commit();
}

CustomField _field({required String id, String fieldTypeId = 'text'}) {
  return CustomField(
    id: id,
    name: 'Field $id',
    fieldType: CustomFieldType.text,
    displayOrder: 0,
    createdAt: DateTime(2024),
    fieldTypeId: fieldTypeId,
  );
}

CustomField _groupField({required String id}) =>
    _field(id: id, fieldTypeId: 'group');

CustomFieldValue _value({required String id, required String customFieldId}) {
  return CustomFieldValue(
    id: id,
    customFieldId: customFieldId,
    memberId: 'member-1',
    value: 'test',
  );
}

void main() {
  late db.AppDatabase database;
  late DriftCustomFieldsRepository repo;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    repo = DriftCustomFieldsRepository(database.customFieldsDao, null);
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'commitValueBatch suppresses emissions during the txn and replays them '
    'post-commit',
    () async {
      await repo.createField(_field(id: 'text-1'));
      await repo.createField(_field(id: 'text-2'));

      // Observe what reaches the FFI. Installed AFTER setup so the field
      // creates above aren't recorded; only the batch's replayed value ops are.
      final emitted = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(emitted.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      var sinkEmptyDuringBody = false;
      final failures = await repo.commitValueBatch(() async {
        final f = <String, Object>{};
        for (final v in [
          _value(id: 'v1', customFieldId: 'text-1'),
          _value(id: 'v2', customFieldId: 'text-2'),
        ]) {
          try {
            await repo.upsertValue(v);
          } catch (e) {
            f[v.customFieldId] = e;
          }
        }
        // Suppression: every emission so far went to the batch's capture sink,
        // not the FFI/test sink. Nothing has been replayed yet.
        sinkEmptyDuringBody = emitted.isEmpty;
        return f;
      });

      expect(failures, isEmpty);
      expect(
        sinkEmptyDuringBody,
        isTrue,
        reason: 'emissions must be deferred past the durable commit',
      );

      // Replayed exactly once each, post-commit, as value creates.
      expect(emitted.map((o) => o.entityId), unorderedEquals(['v1', 'v2']));
      expect(
        emitted.every((o) => o.opType == SyncRecordOpType.create),
        isTrue,
      );
      expect(
        emitted.every((o) => o.table == 'custom_field_values'),
        isTrue,
      );

      // Both values durably committed.
      expect((await repo.getValueForField('text-1', 'member-1'))?.id, 'v1');
      expect((await repo.getValueForField('text-2', 'member-1'))?.id, 'v2');
    },
  );

  test(
    'commitValueBatch persists survivors and emits nothing for a field whose '
    'write threw',
    () async {
      await repo.createField(_field(id: 'text-1'));
      // group-typed fields reject per-member values → upsertValue throws.
      await repo.createField(_groupField(id: 'group-1'));

      final emitted = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(emitted.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final failures = await repo.commitValueBatch(() async {
        final f = <String, Object>{};
        for (final v in [
          _value(id: 'v1', customFieldId: 'text-1'),
          _value(id: 'vg', customFieldId: 'group-1'),
        ]) {
          try {
            await repo.upsertValue(v);
          } catch (e) {
            f[v.customFieldId] = e;
          }
        }
        return f;
      });

      // The group field failed; the text field survived — both inside one txn.
      expect(failures.keys, ['group-1']);
      expect(failures['group-1'], isA<InvalidFieldTypeException>());

      // Survivor durably persisted AND emitted; the failed field neither
      // persisted a value nor produced a replayed op.
      expect((await repo.getValueForField('text-1', 'member-1'))?.id, 'v1');
      expect(
        await database.customFieldsDao.getValueForField('group-1', 'member-1'),
        isNull,
      );
      expect(emitted.map((o) => o.entityId), ['v1']);
    },
  );

  test(
    'commitValueBatch returns the body result and handles deletes via replay',
    () async {
      await repo.createField(_field(id: 'text-1'));
      await repo.upsertValue(_value(id: 'v1', customFieldId: 'text-1'));

      final emitted = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(emitted.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      final result = await repo.commitValueBatch(() async {
        await repo.deleteValue('v1');
        return 'done';
      });

      expect(result, 'done');
      expect(await repo.getValueForField('text-1', 'member-1'), isNull);
      expect(emitted.single.entityId, 'v1');
      expect(emitted.single.opType, SyncRecordOpType.delete);
    },
  );

  test(
    'an uncaught body throw rolls back ALL writes and emits nothing '
    '(single-transaction wrap + safety invariant)',
    () async {
      await repo.createField(_field(id: 'text-1'));

      final emitted = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(emitted.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      await expectLater(
        repo.commitValueBatch(() async {
          // This write completes its own inner upsert — if commitValueBatch
          // did NOT wrap the sweep in one outer transaction, it would persist.
          await repo.upsertValue(_value(id: 'v1', customFieldId: 'text-1'));
          // Uncaught → the outer transaction must roll back everything.
          throw StateError('boom');
        }),
        throwsStateError,
      );

      // Single-transaction proof: v1 was rolled back despite "succeeding".
      expect(await repo.getValueForField('text-1', 'member-1'), isNull);
      // Safety half of the invariant: a rolled-back batch emits NOTHING, even
      // though v1's op was captured before the throw — replay never runs.
      expect(emitted, isEmpty);
    },
  );

  test(
    'real CustomFieldsEditorController.commit wrapped in commitValueBatch: '
    'survivors persist + emit, failed field collected, all in one batch',
    () async {
      await repo.createField(_field(id: 'text-1'));
      await repo.createField(_field(id: 'text-2'));

      // Real controller + real repo; only the leaf editor states are doubles.
      final controller = CustomFieldsEditorController();
      final ok = _StubFieldState(
        'text-1',
        () => repo.upsertValue(_value(id: 'v1', customFieldId: 'text-1')),
      );
      final fails = _StubFieldState(
        'text-2',
        () async => throw Exception('field 2 failed'),
      );
      for (final s in [ok, fails]) {
        controller.register(s);
        controller.markDirty(s, true);
      }

      final emitted = <CapturedSyncOp>[];
      SyncRecordMixin.installCaptureSinkForTesting(emitted.add);
      addTearDown(SyncRecordMixin.removeCaptureSinkForTesting);

      // Exactly how the member sheet flushes staged edits.
      final failures = await repo.commitValueBatch(controller.commit);

      // commit()'s per-field catch surfaced the failed field, keyed by id.
      expect(failures.keys, ['text-2']);
      expect(failures['text-2'], isA<Exception>());
      // Survivor persisted + emitted post-commit; failed field neither.
      expect((await repo.getValueForField('text-1', 'member-1'))?.id, 'v1');
      expect(await repo.getValueForField('text-2', 'member-1'), isNull);
      expect(emitted.map((o) => o.entityId), ['v1']);
    },
  );
}
