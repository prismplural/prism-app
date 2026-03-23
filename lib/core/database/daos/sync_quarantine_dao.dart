import 'package:drift/drift.dart';
import 'package:prism_plurality/core/database/app_database.dart';
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
      select(syncQuarantineTable).get();

  Future<int> count() async {
    final result = await customSelect(
      'SELECT COUNT(*) AS c FROM sync_quarantine',
    ).getSingle();
    return result.read<int>('c');
  }

  Future<void> clearForEntity(String entityType, String entityId) async {
    await (delete(syncQuarantineTable)
          ..where(
            (t) => t.entityType.equals(entityType) & t.entityId.equals(entityId),
          ))
        .go();
  }

  Future<void> clearAll() => delete(syncQuarantineTable).go();

  Future<void> incrementRetry(String id) async {
    await customStatement(
      'UPDATE sync_quarantine SET retry_count = retry_count + 1, '
      'last_retry_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
  }
}
