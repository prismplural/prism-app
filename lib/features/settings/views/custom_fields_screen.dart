import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/widgets/create_edit_field_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';

/// Settings screen for managing custom field definitions.
class CustomFieldsScreen extends ConsumerWidget {
  const CustomFieldsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync = ref.watch(customFieldsProvider);
    final terms = watchTerminology(context, ref);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: context.l10n.settingsCustomFieldsTitle,
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.add,
            tooltip: context.l10n.settingsCustomFieldsAddTooltip,
            onPressed: () => _openCreateSheet(context),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: fieldsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(
          child: Text(context.l10n.settingsCustomFieldsError(e.toString())),
        ),
        data: (fields) {
          if (fields.isEmpty) {
            return EmptyState(
              icon: Icon(AppIcons.tuneOutlined, size: 48),
              title: context.l10n.settingsCustomFieldsEmptyTitle,
              subtitle: context.l10n.settingsCustomFieldsEmptySubtitle(
                terms.singularLower,
              ),
              actionLabel: context.l10n.settingsCustomFieldsAddAction,
              onAction: () => _openCreateSheet(context),
            );
          }

          return _FieldsList(fields: fields);
        },
      ),
    );
  }

  void _openCreateSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) =>
          CreateEditFieldSheet(scrollController: scrollController),
    );
  }
}

class _FieldsList extends ConsumerWidget {
  const _FieldsList({required this.fields});

  final List<CustomField> fields;

  /// Returns only top-level fields (no parentFieldId). Orphaned children
  /// (parentFieldId set but parent missing) remain hidden here; the repo
  /// already promotes them via orphan logic but that is data-layer behaviour.
  List<CustomField> get _topLevelFields =>
      fields.where((f) => f.parentFieldId == null).toList();

  /// Children of [groupId], sorted by displayOrder.
  List<CustomField> _childrenOf(String groupId) => fields
      .where((f) => f.parentFieldId == groupId)
      .toList()
    ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  IconData _iconForField(CustomField field) {
    // Group type is registry-only \u2014 fieldTypeId == 'group'.
    if (field.fieldTypeId == 'group') return AppIcons.folderOutlined;
    return _iconForType(field.fieldType);
  }

  IconData _iconForType(CustomFieldType type) => switch (type) {
    CustomFieldType.text => AppIcons.textFields,
    CustomFieldType.longText => AppIcons.notes,
    CustomFieldType.color => AppIcons.palette,
    CustomFieldType.date => AppIcons.calendarToday,
    CustomFieldType.choice => AppIcons.checkBoxOutlined,
  };

  String _subtitleForField(BuildContext context, CustomField field) {
    if (field.fieldTypeId == 'group') {
      return context.l10n.customFieldTypeGroup;
    }
    if (field.fieldType == CustomFieldType.date &&
        field.datePrecision != null) {
      return '${field.fieldType.localizedLabel(context.l10n)} \u2022 '
          '${field.datePrecision!.localizedLabel(context.l10n)}';
    }
    return field.fieldType.localizedLabel(context.l10n);
  }

  void _onReorder(WidgetRef ref, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final topLevel = _topLevelFields;
    final reordered = List<CustomField>.from(topLevel);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    // Only reorder top-level items. Group children reorder is out of scope
    // for this batch \u2014 cross-group moves land in BATCH 6 Task 16 (long-press
    // menu). Passing only top-level fields here is intentional.
    ref.read(customFieldNotifierProvider.notifier).reorderFields(reordered);
    Haptics.selection();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final topLevel = _topLevelFields;

    return ReorderableListView.builder(
      padding: EdgeInsets.only(top: 8, bottom: NavBarInset.of(context)),
      itemCount: topLevel.length,
      onReorder: (oldIndex, newIndex) => _onReorder(ref, oldIndex, newIndex),
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(12),
            ),
            child: child,
          ),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final field = topLevel[index];
        final isGroup = field.fieldTypeId == 'group';
        final children = isGroup ? _childrenOf(field.id) : <CustomField>[];

        // Groups render as a Column: the group's own row followed by indented
        // child rows. Children are NOT reorderable in this batch; cross-group
        // moves land in BATCH 6 Task 16 (long-press menu).
        return _TopLevelFieldItem(
          key: ValueKey(field.id),
          field: field,
          children: children,
          index: index,
          iconForField: _iconForField,
          subtitleForField: _subtitleForField,
          theme: theme,
        );
      },
    );
  }
}

class _TopLevelFieldItem extends StatelessWidget {
  const _TopLevelFieldItem({
    super.key,
    required this.field,
    required this.children,
    required this.index,
    required this.iconForField,
    required this.subtitleForField,
    required this.theme,
  });

  final CustomField field;
  final List<CustomField> children;
  final int index;
  final IconData Function(CustomField) iconForField;
  final String Function(BuildContext, CustomField) subtitleForField;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldRow(
          field: field,
          index: index,
          iconForField: iconForField,
          subtitleForField: subtitleForField,
          theme: theme,
        ),
        // Indented children (non-reorderable in this batch).
        if (children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final child in children)
                  _FieldRow(
                    key: ValueKey(child.id),
                    field: child,
                    index: -1, // -1 signals: no drag handle
                    iconForField: iconForField,
                    subtitleForField: subtitleForField,
                    theme: theme,
                    isChild: true,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    super.key,
    required this.field,
    required this.index,
    required this.iconForField,
    required this.subtitleForField,
    required this.theme,
    this.isChild = false,
  });

  final CustomField field;
  final int index;
  final IconData Function(CustomField) iconForField;
  final String Function(BuildContext, CustomField) subtitleForField;
  final ThemeData theme;

  /// True when this row is a group child. Children have no drag handle.
  final bool isChild;

  @override
  Widget build(BuildContext context) {
    return PrismListRow(
      leading: Icon(iconForField(field), color: theme.colorScheme.primary),
      title: Text(field.name),
      subtitle: Text(
        subtitleForField(context, field),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isChild)
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                AppIcons.dragHandle,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.4,
                ),
              ),
            ),
          if (!isChild) const SizedBox(width: 8),
          Icon(
            AppIcons.chevronRightRounded,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ],
      ),
      onTap: () => context.push(AppRoutePaths.settingsCustomField(field.id)),
    );
  }
}
