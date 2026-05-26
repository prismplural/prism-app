import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';

/// Render-layer transform: promote orphaned children to the top level for
/// display purposes only.
///
/// A child whose `parentFieldId` references a parent that is either missing
/// from [all], soft-deleted (already filtered out before this function is
/// called — `all` only contains active fields), or is not a group-typed field
/// has its `parentFieldId` cleared in the returned list.
///
/// This is an **in-memory only** transformation. The underlying DB row keeps
/// its `parent_field_id` so the child naturally re-attaches on the next stream
/// emission if the parent comes back via sync or is corrected.
///
/// Repository writes MUST NOT see promoted instances — that would propagate
/// the cleared parent to disk and to peers. This function lives at the render
/// layer; callers that persist (export, sync emission, raw filters) must use
/// the unpromoted stream/snapshot.
List<CustomField> promoteOrphansForRender(List<CustomField> all) {
  if (all.isEmpty) return all;
  final activeIds = all.map((f) => f.id).toSet();
  final fieldById = {for (final f in all) f.id: f};
  return all.map((f) {
    final parentId = f.parentFieldId;
    if (parentId == null) return f;
    // Self-cycle: a buggy peer or sync apply could write parent_field_id ==
    // self_id, which would otherwise render as the field's own child. Always
    // promote.
    if (parentId == f.id) {
      return f.copyWith(parentFieldId: null);
    }
    if (!activeIds.contains(parentId)) {
      // Parent missing or soft-deleted: promote to top level.
      return f.copyWith(parentFieldId: null);
    }
    final parent = fieldById[parentId];
    if (parent != null && parent.fieldTypeId != kGroupFieldTypeId) {
      // Parent exists but is not a group — promote to top level as a
      // defense-in-depth for pre-existing bad data.
      return f.copyWith(parentFieldId: null);
    }
    // Depth-1 enforcement: if the parent itself has a non-null
    // parent_field_id on disk, the child is nested too deeply (depth >= 2).
    // Promote to top level so the render layer is safe even when
    // createFieldFromImport / sync apply / corrupt data plants nested-group
    // structure that the write-side validators would have rejected.
    if (parent != null && parent.parentFieldId != null) {
      return f.copyWith(parentFieldId: null);
    }
    return f;
  }).toList();
}
