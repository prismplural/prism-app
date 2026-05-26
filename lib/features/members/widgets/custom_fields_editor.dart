import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_renderers.dart';
import 'package:prism_plurality/features/members/widgets/field_input_widget.dart';
import 'package:prism_plurality/features/members/widgets/group_field_widgets.dart';
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
    final fieldsAsync = ref.watch(topLevelCustomFieldsProvider);

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
        // Only render top-level fields (parentFieldId == null). Group fields
        // are responsible for rendering their own children. Children with a
        // non-null parentFieldId are skipped here; the group renderer pulls
        // them back in from the same flat provider stream.
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

    if (renderer != null) {
      // Dispatch THROUGH the renderer registry. For the 4 legacy types, the
      // renderer returns a FieldInputWidget. Future types (choice, scale,
      // slider, group) register their own renderer and return a different
      // widget — no edits to this method needed.
      //
      // For legacy types the renderer's editorBuilder creates a bare
      // FieldInputWidget without a controller. We wrap it in
      // _ControllerBoundFieldInput so the controller can coordinate saves.
      // Once all types are either legacy (FieldInputWidget) or self-managing
      // (their own StatefulWidget that doesn't need the controller), this
      // wrapping can be revisited.
      if (def!.id == 'text' ||
          def.id == 'long_text' ||
          def.id == 'color' ||
          def.id == 'date') {
        // All 4 legacy types use FieldInputWidget; give it the controller.
        return _ControllerBoundFieldInput(
          field: field,
          memberId: memberId,
          existingValue: existingValue,
          controller: controller,
        );
      }
      // Group fields: pass the controller so child legacy fields inside the
      // group are also wrapped and register with savePendingValues().
      if (def.id == 'group') {
        return buildGroupEditor(
          context,
          field,
          existingValue,
          memberId,
          controller: controller,
        );
      }
      // Non-legacy, non-group types: delegate entirely to the renderer.
      // These types manage their own save lifecycle.
      return renderer.editorBuilder(context, field, existingValue, memberId);
    }

    // Unknown type — render nothing rather than crashing. Forward-compat: a
    // newer schema may have a type the current build doesn't know about.
    return const SizedBox.shrink();
  }
}

/// Thin wrapper that passes [CustomFieldsEditorController] into [FieldInputWidget].
///
/// All 4 legacy types share [FieldInputWidget] with coordinated saves via
/// the controller. This wrapper lets [CustomFieldsEditor._buildFieldEditor]
/// route through the renderer registry while still providing the controller
/// to the underlying widget.
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
  bool _discarded = false;

  /// True after [discard] has been called. Registered inputs check this in
  /// their own `dispose` and skip the auto-save so cancelled edits don't
  /// leak through to disk during widget teardown.
  @override
  bool get isDiscarded => _discarded;

  Future<void> savePendingValues() async {
    for (final input in List<FieldInputWidgetState>.of(_inputs)) {
      await input.savePendingValue();
    }
  }

  /// Mark the editor as discarded. Wire this from an [UnsavedChangesGuard]'s
  /// `onDiscard` so dropping the sheet doesn't quietly persist in-flight
  /// text in the legacy [FieldInputWidget] save-on-dispose path.
  void discard() {
    _discarded = true;
  }

  void dispose() {
    _inputs.clear();
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
