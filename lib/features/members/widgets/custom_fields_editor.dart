import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/field_input_widget.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

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
    final fieldsAsync = ref.watch(customFieldsProvider);

    return fieldsAsync.when(
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
  }

  Widget _buildEditor(
    BuildContext context,
    WidgetRef ref,
    List<CustomField> fields,
    List<CustomFieldValue> values,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final valueMap = <String, CustomFieldValue>{
      for (final v in values) v.customFieldId: v,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(
              AppIcons.tuneOutlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.memberSectionCustomFields,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final field in fields) ...[
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
    // TODO(task-5): switch to registry.lookupById(field.fieldTypeId) once
    // field.fieldTypeId is on the domain model (Task 5). Until then, bridge
    // via the legacy int.
    final def = customFieldTypeRegistry.lookupByLegacyInt(
      field.fieldType.index,
    );
    if (def != null) {
      // The registry editorBuilder creates a FieldInputWidget for legacy types;
      // future types will have their own stateful widgets. The controller is
      // threaded in via FieldInputWidget's optional parameter — for legacy
      // types the builder creates a FieldInputWidget that accepts the controller
      // via the field_input_widget.dart API.
      return _ControllerBoundFieldInput(
        field: field,
        memberId: memberId,
        existingValue: existingValue,
        controller: controller,
      );
    }
    // Unknown type — render nothing rather than crashing. Forward-compat: a
    // newer schema may have a type the current build doesn't know about.
    return const SizedBox.shrink();
  }
}

/// Thin wrapper that passes [CustomFieldsEditorController] into [FieldInputWidget].
///
/// The registry's [editorBuilder] signature is `(context, field, value, memberId)`
/// and has no slot for the controller. This widget bridges the gap: it creates
/// [FieldInputWidget] directly, giving it the controller, so the controller can
/// call [savePendingValue] on all registered inputs.
class _ControllerBoundFieldInput extends StatelessWidget {
  const _ControllerBoundFieldInput({
    required this.field,
    required this.memberId,
    this.existingValue,
    this.controller,
  });

  final CustomField field;
  final String memberId;
  final CustomFieldValue? existingValue;
  final CustomFieldsEditorController? controller;

  @override
  Widget build(BuildContext context) {
    return FieldInputWidget(
      field: field,
      memberId: memberId,
      existingValue: existingValue,
      controller: controller,
    );
  }
}

/// Controller that coordinates saves across all active [FieldInputWidget]
/// instances within a [CustomFieldsEditor].
///
/// Pass this to [CustomFieldsEditor.controller] and call [savePendingValues]
/// before the parent sheet closes to persist any unsaved (focused) values.
class CustomFieldsEditorController implements CustomFieldsEditorControllerBase {
  final Set<FieldInputWidgetState> _inputs = {};

  Future<void> savePendingValues() async {
    for (final input in List<FieldInputWidgetState>.of(_inputs)) {
      await input.savePendingValue();
    }
  }

  @override
  void register(FieldInputWidgetState input) {
    _inputs.add(input);
  }

  @override
  void unregister(FieldInputWidgetState input) {
    _inputs.remove(input);
  }
}
