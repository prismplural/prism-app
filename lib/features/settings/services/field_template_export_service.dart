import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/core/database/database_providers.dart';
import 'package:prism_plurality/domain/repositories/custom_fields_repository.dart';
import 'package:prism_plurality/domain/custom_fields/field_template.dart';

/// Builds portable [FieldTemplate]s from live field definitions.
/// Never reads or includes per-member values — definitions only.
class FieldTemplateExportService {
  const FieldTemplateExportService(this._repo);

  final CustomFieldsRepository _repo;

  /// Group field [groupId] + every child whose parentFieldId == groupId,
  /// ordered group-first then children by displayOrder.
  Future<FieldTemplate> buildTemplateForGroup(String groupId) async {
    final all = await _repo.getAllFields();

    final group = all.firstWhere((f) => f.id == groupId);
    final children = all
        .where((f) => f.parentFieldId == groupId)
        .toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    return FieldTemplate.fromDomain([group, ...children]);
  }

  /// Single field [fieldId], no children.
  Future<FieldTemplate> buildTemplateForField(String fieldId) async {
    final field = await _repo.getFieldById(fieldId);
    return FieldTemplate.fromDomain([field!]);
  }
}

final fieldTemplateExportServiceProvider =
    Provider<FieldTemplateExportService>((ref) {
  return FieldTemplateExportService(ref.watch(customFieldsRepositoryProvider));
});
