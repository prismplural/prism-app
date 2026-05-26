import 'package:prism_plurality/domain/models/custom_field.dart' as domain;
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart'
    as domain;

abstract class CustomFieldsRepository {
  Stream<List<domain.CustomField>> watchAllFields();

  /// Snapshot of all active (non-deleted) fields with the raw on-disk
  /// `parent_field_id` preserved. Render-layer orphan promotion lives in
  /// `topLevelCustomFieldsProvider` (see
  /// `lib/features/members/providers/custom_fields_providers.dart`); callers
  /// that persist structure (backup export, sync emission) must use this
  /// raw view — promotion is a UI-only transform and would otherwise
  /// permanently flatten parent relationships in exported data.
  Future<List<domain.CustomField>> getAllFields();

  Stream<domain.CustomField?> watchFieldById(String id);
  Future<domain.CustomField?> getFieldById(String id);

  /// UI-flow field creation. Validates parent (must exist, be a group,
  /// not nested) so invalid setup fails loudly. Importer/restore paths
  /// must use [createFieldFromImport] instead.
  Future<void> createField(domain.CustomField field);

  /// Import/restore bypass for [createField]. Skips parent validation so a
  /// backup containing a child whose parent is non-group / soft-deleted /
  /// nested still restores successfully. Render-layer orphan promotion
  /// (`topLevelCustomFieldsProvider`) handles display; the on-disk row
  /// keeps its raw `parent_field_id` so the child re-attaches naturally
  /// if the parent later returns via sync.
  Future<void> createFieldFromImport(domain.CustomField field);

  /// Full-row update. Diffs against the current DB row and emits only
  /// changed fields on the wire. Use this from import/replay paths where
  /// callers legitimately hold a full snapshot.
  ///
  /// **For UI edits, prefer the named patch methods** ([renameField],
  /// [moveFieldToParent], [setFieldDatePrecision], [writeTypedConfig]).
  /// They construct minimal change sets without going through a stale
  /// domain snapshot, eliminating the risk of accidentally writing stale
  /// fields back to disk or to peers.
  Future<void> updateField(domain.CustomField field);

  /// Patch [fieldId]'s `name`. Writes only the name column; sync emits
  /// only `{'name': newName}`. Other columns are untouched on disk and
  /// no other fields are emitted to peers.
  Future<void> renameField(String fieldId, String newName);

  /// Patch [fieldId]'s `parent_field_id`. Pass `null` to move to top level.
  /// Validates the new parent (must exist, be a group, and not itself
  /// nested) before writing. Throws [InvalidFieldTypeException] or
  /// [DepthLimitExceededException] on user-intent invalid moves.
  Future<void> moveFieldToParent(String fieldId, String? newParentId);

  /// Patch [fieldId]'s `date_precision`. Sync emits only that key.
  Future<void> setFieldDatePrecision(
    String fieldId,
    domain.DatePrecision? newPrecision,
  );

  /// Patch [fieldId]'s `display_order`. Single-field write + sync emit.
  /// Prefer [reorderFields] for bulk reorders.
  Future<void> setFieldDisplayOrder(String fieldId, int newOrder);

  Future<void> reorderFields(List<domain.CustomField> fields);
  /// Delete a field by [id].
  ///
  /// For group-typed fields, [deleteChildren] controls what happens to child
  /// fields:
  /// - `false` (default): promotes children to top level by clearing their
  ///   `parentFieldId`. The children remain active.
  /// - `true`: soft-deletes each child individually (each emits its own sync op).
  ///
  /// For non-group fields this parameter has no effect (non-group fields have
  /// no children by the depth-1 invariant).
  Future<void> deleteField(String id, {bool deleteChildren = false});

  Stream<List<domain.CustomFieldValue>> watchValuesForMember(String memberId);
  Stream<List<domain.CustomFieldValue>> watchValuesForField(String fieldId);
  Future<List<domain.CustomFieldValue>> getAllValues();
  Future<domain.CustomFieldValue?> getValueForField(
    String fieldId,
    String memberId,
  );
  Future<void> upsertValue(domain.CustomFieldValue value);
  Future<void> deleteValue(String id);
  Future<void> deleteValuesForField(String fieldId);
  Future<void> deleteValuesForMember(String memberId);

  /// Write a whole-config blob for [fieldId] using the LWW (last-write-wins)
  /// invariant: any config mutation writes the entire blob. No field-level
  /// merge inside the JSON. CRDT convergence depends on this contract.
  ///
  /// First callers land in BATCH 2 (choice option mutations) and beyond.
  Future<void> writeTypedConfig(
    String fieldId,
    CustomFieldTypeConfig newConfig,
  );
}
