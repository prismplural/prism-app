import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:prism_plurality/core/database/daos/sync_quarantine_dao.dart';
import 'package:prism_plurality/core/database/sync_quarantine_kinds.dart';

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

  Future<Map<String, dynamic>?> getDeferredConsumerDelivery(
    String entityType,
    String entityId,
  ) async {
    final rows = await _dao.getDeferredConsumerDeliveries(entityType, entityId);
    if (rows.isEmpty) return null;
    final merged = <String, dynamic>{};
    for (final row in rows) {
      if (row.receivedValue == null) continue;
      final decoded = jsonDecode(row.receivedValue!);
      if (decoded is! Map) {
        throw const FormatException('deferred delivery payload is not a map');
      }
      merged.addAll(decoded.cast<String, dynamic>());
    }
    return merged;
  }

  Future<void> deferConsumerDelivery({
    required String entityType,
    required String entityId,
    required Map<String, dynamic> fields,
    bool overCap = false,
  }) async {
    final prior = await getDeferredConsumerDelivery(entityType, entityId);
    final merged = <String, dynamic>{...?prior, ...fields};
    await _dao.upsertDeferredConsumerDelivery(
      id: 'consumer-delivery-deferred:$entityType:$entityId',
      entityType: entityType,
      entityId: entityId,
      payload: jsonEncode(merged),
      receivedType: overCap
          ? kConsumerDeliverySpillApplyType
          : kConsumerDeliveryDeferredApplyType,
      errorMessage: overCap
          ? '$kConsumerDeliverySpillErrorPrefix; payload preserved for retry'
          : kConsumerDeliveryDeferredErrorPrefix,
    );
  }

  Future<void> clearDeferredConsumerDelivery(
    String entityType,
    String entityId,
  ) => _dao.clearDeferredConsumerDelivery(entityType, entityId);

  Future<bool> hasConsumerDeliveryTombstone(
    String entityType,
    String entityId,
  ) => _dao.hasConsumerDeliveryTombstone(entityType, entityId);

  Future<void> markConsumerDeliveryTombstone(
    String entityType,
    String entityId,
  ) => _dao.markConsumerDeliveryTombstone(
    id: 'consumer-delivery-tombstone:$entityType:$entityId',
    entityType: entityType,
    entityId: entityId,
  );

  Future<int> repairLegacyMemberAgeStringMismatches() =>
      _dao.repairLegacyMemberAgeStringMismatches();

  Future<void> clearAll() async {
    await repairLegacyMemberAgeStringMismatches();
    await _dao.clearAll();
  }
}
