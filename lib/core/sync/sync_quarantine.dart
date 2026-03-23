import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/daos/sync_quarantine_dao.dart';

/// Service that records field-level sync failures into the quarantine table
/// instead of silently dropping mismatched data.
class SyncQuarantineService {
  SyncQuarantineService(this._dao);

  final SyncQuarantineDao _dao;

  Future<void> quarantineField({
    required String entityType,
    required String entityId,
    String? fieldName,
    required String expectedType,
    required String receivedType,
    String? receivedValue,
    String? sourceDevice,
    String? errorMessage,
  }) async {
    await _dao.quarantineField(
      id: const Uuid().v4(),
      entityType: entityType,
      entityId: entityId,
      fieldName: fieldName,
      expectedType: expectedType,
      receivedType: receivedType,
      receivedValue: receivedValue,
      sourceDevice: sourceDevice,
      errorMessage: errorMessage,
    );
  }

  Future<bool> hasQuarantinedItems() async => (await _dao.count()) > 0;

  Future<int> count() => _dao.count();

  Future<void> clearAll() => _dao.clearAll();
}
