import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_editor_scope.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_renderers.dart';

export 'package:prism_plurality/features/members/widgets/custom_field_editor_scope.dart'
    show CustomFieldsEditorController, CustomFieldEditorScope, PendingFieldEditState;

/// Inline editor for custom field values on the member edit sheet.
class CustomFieldsEditor extends ConsumerWidget {
  const CustomFieldsEditor({
    super.key,
    required this.memberId,
    this.controller,
  });

  final String memberId;
  final CustomFieldsEditorController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync = ref.watch(topLevelCustomFieldsProvider);

    final body = fieldsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (fields) {
        if (fields.isEmpty) return const SizedBox.shrink();

        final valuesAsync = ref.watch(
          memberCustomFieldValuesProvider(memberId),
        );
        return valuesAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (values) => _buildEditor(context, ref, fields, values),
        );
      },
    );

    final c = controller;
    if (c == null) return body;
    return CustomFieldEditorScope(controller: c, child: body);
  }

  Widget _buildEditor(
    BuildContext context,
    WidgetRef ref,
    List<CustomField> fields,
    List<CustomFieldValue> values,
  ) {
    final valueMap = <String, CustomFieldValue>{
      for (final v in values) v.customFieldId: v,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top-level fields only — group renderers pull their children from the
        // same provider stream.
        for (final field in fields.where((f) => f.parentFieldId == null)) ...[
          _buildFieldEditor(context, field, valueMap[field.id]),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildFieldEditor(
    BuildContext context,
    CustomField field,
    CustomFieldValue? existingValue,
  ) {
    final def = customFieldTypeRegistry.lookupById(field.fieldTypeId);
    final renderer = rendererFor(def);
    // Unknown type — forward-compat: a newer schema may carry types this
    // build doesn't know about.
    if (renderer == null) return const SizedBox.shrink();
    return renderer.editorBuilder(context, field, existingValue, memberId);
  }
}
