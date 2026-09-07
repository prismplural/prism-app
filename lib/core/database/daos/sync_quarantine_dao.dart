import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/sync_quarantine_kinds.dart';
import 'package:prism_plurality/core/database/tables/sync_quarantine_table.dart';

part 'sync_quarantine_dao.g.dart';

@DriftAccessor(tables: [SyncQuarantineTable])
class SyncQuarantineDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQuarantineDaoMixin {
  SyncQuarantineDao(super.db);

  Future<void> quarantineField({
    required String id,
    required String entityType,
    required String entityId,
    String? fieldName,
    required String expectedType,
    required String receivedType,
    String? receivedValue,
    String? sourceDevice,
    String? errorMessage,
  }) async {
    await into(syncQuarantineTable).insertOnConflictUpdate(
      SyncQuarantineTableCompanion.insert(
        id: id,
        entityType: entityType,
        entityId: entityId,
        fieldName: Value(fieldName),
        expectedType: expectedType,
        receivedType: receivedType,
        receivedValue: Value(receivedValue),
        sourceDevice: Value(sourceDevice),
        retryCount: const Value(0),
        createdAt: DateTime.now(),
        errorMessage: Value(errorMessage),
      ),
    );
  }

  Future<List<SyncQuarantineData>> getAll() =>
      (select(syncQuarantineTable)..where(
            (t) => t.receivedType.equals(kConsumerDeliveryTombstoneType).not(),
          ))
          .get();

  Future<List<SyncQuarantineData>> getConsumerDeliverySpillRows({
    int limit = 500,
  }) {
    return (select(syncQuarantineTable)
          ..where(
            (t) =>
                t.expectedType.equals(kConsumerDeliverySpillExpectedType) &
                t.fieldName.isNull() &
                (((t.receivedType.equals(kConsumerDeliverySpillApplyType) |
                            t.receivedType.equals(
                              kConsumerDeliverySpillDeleteType,
                            )) &
                        t.errorMessage.like(kConsumerDeliverySpillErrorLike)) |
                    t.receivedType.equals(kConsumerDeliveryDeferredApplyType)),
          )
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.retryCount, mode: OrderingMode.asc),
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc),
          ])
          ..limit(limit))
        .get();
  }

  Future<List<SyncQuarantineData>> getDeferredConsumerDeliveries(
    String entityType,
    String entityId,
  ) {
    return (select(syncQuarantineTable)
          ..where(
            (t) =>
                t.entityType.equals(entityType) &
                t.entityId.equals(entityId) &
                t.fieldName.isNull() &
                (t.receivedType.equals(kConsumerDeliveryDeferredApplyType) |
                    t.receivedType.equals(kConsumerDeliverySpillApplyType)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<void> upsertDeferredConsumerDelivery({
    required String id,
    required String entityType,
    required String entityId,
    required String payload,
    String receivedType = kConsumerDeliveryDeferredApplyType,
    String errorMessage = kConsumerDeliveryDeferredErrorPrefix,
  }) async {
    await into(syncQuarantineTable).insertOnConflictUpdate(
      SyncQuarantineTableCompanion.insert(
        id: id,
        entityType: entityType,
        entityId: entityId,
        fieldName: const Value(null),
        expectedType: kConsumerDeliverySpillExpectedType,
        receivedType: receivedType,
        receivedValue: Value(payload),
        createdAt: DateTime.now(),
        errorMessage: Value(errorMessage),
      ),
    );
  }

  Future<void> clearDeferredConsumerDelivery(
    String entityType,
    String entityId,
  ) async {
    await (delete(syncQuarantineTable)..where(
          (t) =>
              t.entityType.equals(entityType) &
              t.entityId.equals(entityId) &
              (t.receivedType.equals(kConsumerDeliveryDeferredApplyType) |
                  t.receivedType.equals(kConsumerDeliverySpillApplyType)),
        ))
        .go();
  }

  Future<bool> hasConsumerDeliveryTombstone(
    String entityType,
    String entityId,
  ) async {
    final row =
        await (select(syncQuarantineTable)..where(
              (t) =>
                  t.entityType.equals(entityType) &
                  t.entityId.equals(entityId) &
                  t.receivedType.equals(kConsumerDeliveryTombstoneType),
            ))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> markConsumerDeliveryTombstone({
    required String id,
    required String entityType,
    required String entityId,
  }) async {
    await into(syncQuarantineTable).insertOnConflictUpdate(
      SyncQuarantineTableCompanion.insert(
        id: id,
        entityType: entityType,
        entityId: entityId,
        fieldName: const Value(null),
        expectedType: 'deleted',
        receivedType: kConsumerDeliveryTombstoneType,
        createdAt: DateTime.now(),
        errorMessage: const Value(
          'absorbing consumer-delivery tombstone; delayed fields are subsumed',
        ),
      ),
    );
  }

  Future<List<SyncQuarantineData>> getDeferredPkEntryUnresolved() {
    return (select(syncQuarantineTable)..where(
          (t) =>
              t.entityType.equals('member_group_entries') &
              t.receivedType.equals('DeferredPkEntryUnresolved'),
        ))
        .get();
  }

  Future<int> repairLegacyMemberAgeStringMismatches() async {
    return transaction(() async {
      final rows = await customSelect(
        '''
        SELECT id, entity_id, received_value
        FROM sync_quarantine
        WHERE entity_type = 'members'
          AND field_name = 'age'
          AND received_type = 'String'
          AND received_value IS NOT NULL
          AND (
            lower(expected_type) IN ('int', 'int?')
            OR error_message LIKE 'Type mismatch: expected int%got String'
          )
        ORDER BY created_at DESC
        ''',
        readsFrom: {syncQuarantineTable},
      ).get();

      var repaired = 0;
      final repairedEntityIds = <String>{};
      for (final row in rows) {
        final entityId = row.read<String>('entity_id');
        if (repairedEntityIds.contains(entityId)) continue;

        final receivedValue = row.read<String?>('received_value');
        if (receivedValue == null) continue;

        final updated = await customUpdate(
          '''
          UPDATE members
          SET age = ?
          WHERE id = ?
            AND (age IS NULL OR age = '')
          ''',
          variables: [
            Variable<String>(receivedValue),
            Variable<String>(entityId),
          ],
          updates: {db.members},
        );

        if (updated > 0) {
          repaired++;
          repairedEntityIds.add(entityId);
        }
      }

      for (final entityId in repairedEntityIds) {
        await customUpdate(
          '''
          DELETE FROM sync_quarantine
          WHERE entity_type = 'members'
            AND field_name = 'age'
            AND received_type = 'String'
            AND received_value IS NOT NULL
            AND (
              lower(expected_type) IN ('int', 'int?')
              OR error_message LIKE 'Type mismatch: expected int%got String'
            )
            AND entity_id = ?
          ''',
          variables: [Variable<String>(entityId)],
          updates: {syncQuarantineTable},
        );
      }

      return repaired;
    });
  }

  Future<int> count() async {
    final result = await customSelect(
      'SELECT COUNT(*) AS c FROM sync_quarantine WHERE received_type != ?',
      variables: [Variable.withString(kConsumerDeliveryTombstoneType)],
    ).getSingle();
    return result.read<int>('c');
  }

  Future<void> clearForEntity(String entityType, String entityId) async {
    await (delete(syncQuarantineTable)..where(
          (t) => t.entityType.equals(entityType) & t.entityId.equals(entityId),
        ))
        .go();
  }

  Future<void> clearAll() =>
      (delete(syncQuarantineTable)..where(
            (t) => t.receivedType.equals(kConsumerDeliveryTombstoneType).not(),
          ))
          .go();

  Future<void> deleteById(String id) =>
      (delete(syncQuarantineTable)..where((t) => t.id.equals(id))).go();

  Future<void> incrementRetry(String id) async {
    await customStatement(
      'UPDATE sync_quarantine SET retry_count = retry_count + 1, '
      'last_retry_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
  }
}
