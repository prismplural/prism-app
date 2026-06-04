import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_editor_scope.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_renderers.dart';

export 'package:prism_plurality/features/members/widgets/custom_field_editor_scope.dart'
    show
        CustomFieldsEditorController,
        CustomFieldEditorScope,
        PendingFieldEditState;

/// Inline editor for custom field values on the member edit sheet.
class CustomFieldsEditor extends ConsumerWidget {
  const CustomFieldsEditor({
    super.key,
    required this.memberId,
    this.controller,
    this.scrollController,
    this.scrollViewKey,
    this.padding,
    this.openLongTextEditor,
  });

  final String memberId;
  final CustomFieldsEditorController? controller;
  final ScrollController? scrollController;
  final Key? scrollViewKey;
  final EdgeInsetsGeometry? padding;
  final LongTextFieldEditorOpener? openLongTextEditor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync = ref.watch(topLevelCustomFieldsProvider);

    final body = fieldsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (fields) {
        final topLevelFields = fields
            .where((f) => f.parentFieldId == null)
            .toList(growable: false);
        if (topLevelFields.isEmpty) return const SizedBox.shrink();

        final valuesAsync = ref.watch(
          memberCustomFieldValuesProvider(memberId),
        );
        return valuesAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (values) => _buildEditor(context, topLevelFields, values),
        );
      },
    );

    final c = controller;
    if (c == null) return body;
    return CustomFieldEditorScope(
      controller: c,
      openLongTextEditor: openLongTextEditor,
      child: body,
    );
  }

  Widget _buildEditor(
    BuildContext context,
    List<CustomField> fields,
    List<CustomFieldValue> values,
  ) {
    final valueMap = <String, CustomFieldValue>{
      for (final v in values) v.customFieldId: v,
    };

    return ListView.separated(
      key: scrollViewKey,
      controller: scrollController,
      padding: padding,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: fields.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final field = fields[index];
        return _buildFieldEditor(context, field, valueMap[field.id]);
      },
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
    return KeyedSubtree(
      key: ValueKey<String>('custom-field-editor-${field.id}'),
      child: renderer.editorBuilder(context, field, existingValue, memberId),
    );
  }
}
