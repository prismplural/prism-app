// Correctness contract for `commitValueBatch`: one durable transaction whose
// sync emissions are persisted into the durable outbox INSIDE the transaction
// (atomic with the value writes) and dispatched only post-commit, with the
// caller's per-field partial-failure semantics preserved.
//
// `commitValueBatch` now delegates to `runSyncedWrite`, so the captured
// ops land as durable `sync_op_outbox` rows committed atomically with the value
// rows — no in-memory post-commit replay. We observe emissions by reading the
// outbox table (the drain trigger is left unwired, so the rows simply sit there
// for inspection). A never-paired device persists nothing; these tests flip
// `syncCredentialsPersisted` true right before the batch so setup field-creates
// do not pollute the outbox.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_sync/generated/api.dart' as ffi;

import 'package:prism_plurality/core/database/app_database.dart' as db;
import 'package:prism_plurality/core/sync/sync_outbox_drainer.dart';
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/domain/custom_fields/custom_fields_exceptions.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_editor_scope.dart';

/// Test double for a single staged editor. Mirrors what the real per-field
/// editor's `commitPendingValue` does (write via repo, or fail), so the REAL
/// [CustomFieldsEditorController.commit] partial-failure loop runs against the
/// REAL [DriftCustomFieldsRepository.commitValueBatch]. Only the leaf
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

class _FakeHandle implements ffi.PrismSyncHandle {
  const _FakeHandle();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
    // Default to never-paired during setup so field-create emissions don't
    // populate the outbox; individual tests flip this true before the batch.
    syncCredentialsPersisted.value = false;
  });

  tearDown(() async {
    syncCredentialsPersisted.value = false;
    await database.close();
  });

  /// Read the outbox rows for `custom_field_values`, in drain (id) order.
  Future<List<db.SyncOpOutboxRow>> outboxValueRows() async {
    final rows = await database.syncOutboxDao.allInIdOrder();
    return rows.where((r) => r.entityTable == 'custom_field_values').toList();
  }

  test(
    'commitValueBatch defers emissions during the txn and persists them to '
    'the outbox post-commit',
    () async {
      await repo.createField(_field(id: 'text-1'));
      await repo.createField(_field(id: 'text-2'));
      // From here on, emissions are durable. Setup creates above produced none.
      syncCredentialsPersisted.value = true;

      var outboxEmptyDuringBody = false;
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
        // The captured ops are persisted only at the END of the transaction,
        // so mid-body the outbox holds nothing — the durable enqueue is
        // deferred past the value writes.
        outboxEmptyDuringBody = (await outboxValueRows()).isEmpty;
        return f;
      });

      expect(failures, isEmpty);
      expect(
        outboxEmptyDuringBody,
        isTrue,
        reason: 'emissions must be persisted past the durable commit',
      );

      // Persisted exactly once each, in capture order, as value creates.
      final rows = await outboxValueRows();
      expect(rows.map((r) => r.entityId), ['v1', 'v2']);
      expect(rows.every((r) => r.opType == 'create'), isTrue);

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
      syncCredentialsPersisted.value = true;

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

      // group field failed; text field survived — both inside one txn.
      expect(failures.keys, ['group-1']);
      expect(failures['group-1'], isA<InvalidFieldTypeException>());

      // Survivor durably persisted AND enqueued; failed field neither persisted
      // a value nor produced an outbox row.
      expect((await repo.getValueForField('text-1', 'member-1'))?.id, 'v1');
      expect(
        await database.customFieldsDao.getValueForField('group-1', 'member-1'),
        isNull,
      );
      final rows = await outboxValueRows();
      expect(rows.map((r) => r.entityId), ['v1']);
    },
  );

  test(
    'commitValueBatch returns the body result and handles deletes via the '
    'outbox',
    () async {
      await repo.createField(_field(id: 'text-1'));
      await repo.upsertValue(_value(id: 'v1', customFieldId: 'text-1'));
      syncCredentialsPersisted.value = true;

      final result = await repo.commitValueBatch(() async {
        await repo.deleteValue('v1');
        return 'done';
      });

      expect(result, 'done');
      expect(await repo.getValueForField('text-1', 'member-1'), isNull);
      final rows = await outboxValueRows();
      expect(rows.single.entityId, 'v1');
      expect(rows.single.opType, 'delete');
    },
  );

  test(
    'crash-sim: an N-field commitValueBatch survives a "relaunch" — a fresh '
    'drainer over the same DB dispatches all N ops',
    () async {
      for (final id in ['f1', 'f2', 'f3']) {
        await repo.createField(_field(id: id));
      }
      syncCredentialsPersisted.value = true;

      // Commit N field values in one batch. No drainer is wired, so the rows
      // are persisted but never dispatched — simulating a crash after the
      // durable commit but before emission.
      await repo.commitValueBatch(() async {
        for (final id in ['f1', 'f2', 'f3']) {
          await repo.upsertValue(_value(id: 'v-$id', customFieldId: id));
        }
      });
      final pending = await outboxValueRows();
      expect(pending.map((r) => r.entityId), ['v-f1', 'v-f2', 'v-f3']);

      // "Relaunch": a fresh drainer over the same DB recovers and dispatches
      // every op — no edit by the user required.
      final dispatched = <String>[];
      final drainer = SyncOutboxDrainer(
        database,
        dispatchOp: (h, op) async => dispatched.add(op.entityId),
      );
      await drainer.drain(const _FakeHandle());

      expect(dispatched, ['v-f1', 'v-f2', 'v-f3']);
      expect(await outboxValueRows(), isEmpty);
    },
  );

  test(
    'an uncaught body throw rolls back ALL writes and persists nothing '
    '(single-transaction wrap + safety invariant)',
    () async {
      await repo.createField(_field(id: 'text-1'));
      syncCredentialsPersisted.value = true;

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
      // Safety half of the invariant: a rolled-back batch persists NOTHING —
      // the outbox rows roll back atomically with the value rows.
      expect(await outboxValueRows(), isEmpty);
    },
  );

  test(
    'real CustomFieldsEditorController.commit wrapped in commitValueBatch: '
    'survivors persist + emit, failed field collected, all in one batch',
    () async {
      await repo.createField(_field(id: 'text-1'));
      await repo.createField(_field(id: 'text-2'));
      syncCredentialsPersisted.value = true;

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

      // Exactly how the member sheet flushes staged edits.
      final failures = await repo.commitValueBatch(controller.commit);

      // commit()'s per-field catch surfaced the failed field, keyed by id.
      expect(failures.keys, ['text-2']);
      expect(failures['text-2'], isA<Exception>());
      // Survivor persisted + enqueued post-commit; failed field neither.
      expect((await repo.getValueForField('text-1', 'member-1'))?.id, 'v1');
      expect(await repo.getValueForField('text-2', 'member-1'), isNull);
      final rows = await outboxValueRows();
      expect(rows.map((r) => r.entityId), ['v1']);
    },
  );
}
