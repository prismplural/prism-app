// F42 contract: the custom_field_values apply path must not blank a value when
// the apply throws mid-write. The logical-dedup branch tombstones the OLD row
// and writes the replacement; on the pre-fix ordering (tombstone first) a throw
// on the replacement write left the value soft-deleted with no successor (the
// chunk txn still commits — per-row failures are caught). The fix writes the
// replacement BEFORE the old-row tombstone, so the same throw leaves the value
// intact. This test forces a throw on the value-payload write and asserts a
// live value survives — it fails on the pre-fix ordering.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:prism_plurality/core/constants/custom_field_namespaces.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/sync/drift_sync_adapter.dart';

/// Throws on the UPDATE that writes [payload] into custom_field_values (the
/// replacement write), letting the is_deleted tombstone UPDATE through. Mimics a
/// mid-apply failure on the value write regardless of statement ordering.
class _FailOnValueWrite extends QueryInterceptor {
  _FailOnValueWrite(this.payload);
  final String payload;

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.contains('custom_field_values') && args.contains(payload)) {
      throw StateError('simulated mid-apply failure on value write');
    }
    return executor.runUpdate(statement, args);
  }
}

void main() {
  const fieldId = 'field-1';
  const memberId = 'member-1';
  final deterministicId = deriveCustomFieldValueId(
    customFieldId: fieldId,
    memberId: memberId,
  );

  test(
    'apply throwing on the replacement write does not blank the surviving value',
    () async {
      const payload = 'incoming';
      final db = AppDatabase(
        NativeDatabase.memory().interceptWith(_FailOnValueWrite(payload)),
      );
      addTearDown(db.close);

      // Seed the convergence scenario the dedup branch handles:
      //  - a tombstoned row at the deterministic id (burned by a prior clear)
      //  - an active logical row under a minted id holding the current value
      await db
          .into(db.customFieldValues)
          .insert(
            CustomFieldValuesCompanion.insert(
              id: deterministicId,
              customFieldId: fieldId,
              memberId: memberId,
              value: 'old',
              isDeleted: const Value(true),
            ),
          );
      const mintedId = 'minted-1';
      await db
          .into(db.customFieldValues)
          .insert(
            CustomFieldValuesCompanion.insert(
              id: mintedId,
              customFieldId: fieldId,
              memberId: memberId,
              value: 'survivor',
              isDeleted: const Value(false),
            ),
          );

      final entity = buildSyncAdapterWithCompletion(db).adapter.entities
          .singleWhere((e) => e.tableName == 'custom_field_values');

      // Incoming op carries the deterministic id → resolves targetId to the
      // deterministic row (existingByTarget != null), existingLogical is the
      // minted row → the dedup branch runs and its value write throws.
      await expectLater(
        entity.applyFields(deterministicId, {
          'custom_field_id': fieldId,
          'member_id': memberId,
          'value': payload,
          'is_deleted': false,
        }),
        throwsA(isA<StateError>()),
      );

      // The surviving value must still be live and readable (not blanked).
      final active = await (db.select(
        db.customFieldValues,
      )..where((v) => v.isDeleted.equals(false))).get();
      expect(active, isNotEmpty, reason: 'value was blanked with no successor');
      expect(active.map((v) => v.value), contains('survivor'));
    },
  );
}
