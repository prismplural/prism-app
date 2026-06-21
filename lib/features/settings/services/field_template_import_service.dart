import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/app_database.dart';
import 'package:prism_plurality/core/database/database_provider.dart';
import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/core/sync/prism_sync_providers.dart'
    show triggerOutboxDrain;
import 'package:prism_plurality/core/sync/sync_runtime_state.dart';
import 'package:prism_plurality/core/sharing/field_template_codec.dart';
import 'package:prism_plurality/data/repositories/drift_custom_fields_repository.dart';
import 'package:prism_plurality/data/repositories/sync_record_mixin.dart';
import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';

/// Result of a successful template import.
class ImportedTemplateResult {
  const ImportedTemplateResult({
    required this.fieldsImported,
    required this.groupIds,
  });

  /// Total number of custom_field rows created.
  final int fieldsImported;

  /// IDs of the top-level group field(s) created by this import (for
  /// navigation / success-toast use).
  final List<String> groupIds;
}

/// Imports a [FieldTemplate] as new independent custom fields.
///
/// Every import creates FRESH UUIDs — this is NOT an upsert/restore path. Two
/// imports of the same template produce two independent groups, which is the
/// correct "install a community template" semantic.
///
/// Wraps writes in [SyncRecordMixin.runFencedEmissionTransaction] so field rows
/// and their outbox sync-op rows commit atomically; a rollback leaves zero data
/// rows AND zero outbox rows (no phantom ops).
class FieldTemplateImportService {
  const FieldTemplateImportService(this._db, this._repo);

  final AppDatabase _db;
  // DriftCustomFieldsRepository rather than the abstract interface because
  // createFieldAtEnd (assigns end display-order + validates depth) is concrete
  // and is exactly what a template import needs.
  final DriftCustomFieldsRepository _repo;

  Future<ImportedTemplateResult> importTemplate(FieldTemplate t) async {
    // MANDATORY: validate + normalize before any DB write. This is a public
    // entry point; never assume the caller pre-validated.
    final norm = const FieldTemplateCodec().validateAndNormalize(t);
    // A malformed compactConfig can pass structural validation but throw a raw
    // _TypeError/ArgumentError when inflated; surface it as a typed invalid so
    // callers only ever handle FieldTemplateCodecException (and never crash).
    final List<CustomField> fields;
    try {
      fields = norm.toDomainFields();
    } on FieldTemplateCodecException {
      rethrow;
    } catch (e) {
      throw FieldTemplateCodecException(
        FieldTemplateCodecError.invalid,
        'Template config could not be materialized: $e',
      );
    }

    // Sort so every group precedes its children. Groups have no parentFieldId;
    // children do. The group must be inserted first so each child's end
    // display-order computes within the parent's scope and links correctly.
    final sorted = [
      ...fields.where((f) => f.parentFieldId == null),
      ...fields.where((f) => f.parentFieldId != null),
    ];

    final groupIds = sorted
        .where((f) => f.fieldTypeId == kGroupFieldTypeId)
        .map((f) => f.id)
        .toList();

    final captured = <CapturedSyncOp>[];
    await SyncRecordMixin.runFencedEmissionTransaction(_db, () async {
      for (final field in sorted) {
        await _repo.createFieldAtEnd(field);
      }
      // Persist captured ops INSIDE the transaction so data rows + outbox rows
      // commit atomically. Gated on credentials — never-paired devices enqueue
      // nothing (bootstrapExistingData seeds at pairing).
      if (syncCredentialsPersisted.value) {
        await SyncRecordMixin.persistCapturedOpsToOutbox(_db, captured);
      }
    }, captured.add);

    // Post-commit drain: outbox rows (if any) are now durable; fire the drainer.
    // syncCredentialsPersisted.value re-read intentionally (mirrors data_import_service).
    if (syncCredentialsPersisted.value && captured.isNotEmpty) {
      await triggerOutboxDrain(_db, syncCurrentHandle.value);
    }

    return ImportedTemplateResult(
      fieldsImported: sorted.length,
      groupIds: groupIds,
    );
  }
}

final fieldTemplateImportServiceProvider =
    Provider<FieldTemplateImportService>((ref) {
  // customFieldsRepositoryProvider always returns DriftCustomFieldsRepository;
  // the abstract type is widened at the provider boundary.
  final repo =
      ref.watch(customFieldsRepositoryProvider) as DriftCustomFieldsRepository;
  return FieldTemplateImportService(ref.watch(databaseProvider), repo);
});
