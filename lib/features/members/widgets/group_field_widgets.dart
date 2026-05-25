import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_renderers.dart';
import 'package:prism_plurality/features/settings/widgets/create_edit_field_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';

// ─── Editor ───────────────────────────────────────────────────────────────────

/// Builds the interactive group editor widget. Called by the renderer registry.
Widget buildGroupEditor(
  BuildContext context,
  CustomField field,
  CustomFieldValue? value,
  String memberId,
) {
  return _GroupEditorWidget(field: field, memberId: memberId);
}

/// Stateful editor for a Group custom field. Renders a left-border inset
/// container with child fields rendered as nested editor inputs.
///
/// Watches [customFieldsProvider] to find children where
/// [CustomField.parentFieldId] matches [field.id].
class _GroupEditorWidget extends ConsumerWidget {
  const _GroupEditorWidget({required this.field, required this.memberId});

  final CustomField field;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final fieldsAsync = ref.watch(customFieldsProvider);
    final valuesAsync = ref.watch(memberCustomFieldValuesProvider(memberId));

    return fieldsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (allFields) => valuesAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (values) {
          final valueMap = <String, CustomFieldValue>{
            for (final v in values) v.customFieldId: v,
          };

          final children = allFields
              .where((f) => f.parentFieldId == field.id)
              .toList()
            ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

          return _GroupInsetContainer(
            field: field,
            theme: theme,
            child: children.isEmpty
                ? _EmptyGroupButton(
                    label: l10n.customFieldGroupAddChildButton,
                    onTap: () => _openAddChildSheet(context),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        _buildChildEditor(
                          context,
                          children[i],
                          valueMap[children[i].id],
                        ),
                      ],
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildChildEditor(
    BuildContext context,
    CustomField child,
    CustomFieldValue? existingValue,
  ) {
    final def = customFieldTypeRegistry.lookupById(child.fieldTypeId);
    final renderer = rendererFor(def);
    if (renderer != null) {
      return renderer.editorBuilder(context, child, existingValue, memberId);
    }
    // Legacy types without a registry entry fall through to SizedBox.
    return const SizedBox.shrink();
  }

  void _openAddChildSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (ctx, scrollController) => CreateEditFieldSheet(
        scrollController: scrollController,
        parentFieldId: field.id,
      ),
    );
  }
}

// ─── Display ──────────────────────────────────────────────────────────────────

/// Builds the read-only display widget for a Group field.
///
/// The value parameter is ignored (groups have no per-member value). The widget
/// watches the providers directly. Returns [SizedBox.shrink] when all children
/// have empty values.
Widget buildGroupDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return _GroupDisplayWidget(field: field);
}

class _GroupDisplayWidget extends ConsumerWidget {
  const _GroupDisplayWidget({required this.field});

  final CustomField field;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group display widgets are rendered inside _FieldValueBody which already
    // has the member's values available. However, _FieldValueBody doesn't pass
    // them down and there's no memberId in scope here. The display context
    // (CustomFieldsDisplay) renders each field individually. Since groups are
    // filtered out of the top-level iteration (parentFieldId == null filter),
    // this widget is only reached when groups are explicitly dispatched to.
    // For now, hide — the group's children are rendered directly.
    //
    // In a future batch, a memberId-aware GroupDisplay can watch the right
    // provider here. For Task 10, the top-level filter in CustomFieldsDisplay
    // prevents double-rendering children AND groups at the top level.
    return const SizedBox.shrink();
  }
}

// ─── Compact ──────────────────────────────────────────────────────────────────

/// Builds the compact list-row display for a Group field.
///
/// Groups have no per-member value; the compact view is always hidden.
Widget buildGroupCompact(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return const SizedBox.shrink();
}

// ─── Shared containers ────────────────────────────────────────────────────────

/// The bordered left-inset container shared by group editor and display.
///
/// Uses a 4dp [outlineVariant]-colored left border — NOT card chrome — so
/// groups feel structural without producing a wall of cards (per BATCH 1
/// designer feedback).
class _GroupInsetContainer extends StatelessWidget {
  const _GroupInsetContainer({
    required this.field,
    required this.theme,
    required this.child,
  });

  final CustomField field;
  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hasName = field.name.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 4,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasName) ...[
            Row(
              children: [
                Icon(
                  AppIcons.folderOutlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    field.name,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }
}

/// Empty-state button shown inside an empty group editor.
class _EmptyGroupButton extends StatelessWidget {
  const _EmptyGroupButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(AppIcons.add, size: 16),
      label: Text(label),
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
