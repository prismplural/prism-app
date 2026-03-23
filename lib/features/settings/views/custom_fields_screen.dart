import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/settings/widgets/create_edit_field_sheet.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

/// Settings screen for managing custom field definitions.
class CustomFieldsScreen extends ConsumerWidget {
  const CustomFieldsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync = ref.watch(customFieldsProvider);

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: 'Custom Fields',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: Icons.add,
            tooltip: 'Add field',
            onPressed: () => _openCreateSheet(context),
          ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: fieldsAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (fields) {
          if (fields.isEmpty) {
            return EmptyState(
              icon: Icons.tune_outlined,
              title: 'No custom fields',
              subtitle:
                  'Add fields to track custom attributes for each member',
              actionLabel: 'Add Field',
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
      builder: (context, scrollController) => CreateEditFieldSheet(
        scrollController: scrollController,
      ),
    );
  }
}

class _FieldsList extends ConsumerWidget {
  const _FieldsList({required this.fields});

  final List<CustomField> fields;

  IconData _iconForType(CustomFieldType type) => switch (type) {
        CustomFieldType.text => Icons.text_fields,
        CustomFieldType.color => Icons.palette,
        CustomFieldType.date => Icons.calendar_today,
      };

  String _subtitleForField(CustomField field) {
    if (field.fieldType == CustomFieldType.date && field.datePrecision != null) {
      return '${field.fieldType.label} \u2022 ${field.datePrecision!.label}';
    }
    return field.fieldType.label;
  }

  void _onReorder(WidgetRef ref, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<CustomField>.from(fields);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    ref.read(customFieldNotifierProvider.notifier).reorderFields(reordered);
    Haptics.selection();
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    CustomField field,
  ) async {
    final confirmed = await PrismDialog.confirm(
      context: context,
      title: 'Delete Field',
      message:
          'Are you sure you want to delete "${field.name}"? This will delete the field and all its values.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) {
      Haptics.heavy();
      ref.read(customFieldNotifierProvider.notifier).deleteField(field.id);
      if (context.mounted) {
        PrismToast.show(context, message: '${field.name} deleted');
      }
    }
  }

  void _openEditSheet(BuildContext context, CustomField field) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => CreateEditFieldSheet(
        scrollController: scrollController,
        field: field,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ReorderableListView.builder(
      padding: EdgeInsets.only(top: 8, bottom: NavBarInset.of(context)),
      itemCount: fields.length,
      onReorder: (oldIndex, newIndex) => _onReorder(ref, oldIndex, newIndex),
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final field = fields[index];
        return Dismissible(
          key: ValueKey(field.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: theme.colorScheme.error,
            child: Icon(Icons.delete, color: theme.colorScheme.onError),
          ),
          confirmDismiss: (_) async {
            await _confirmDelete(context, ref, field);
            return false;
          },
          child: ListTile(
            key: ValueKey(field.id),
            leading: Icon(
              _iconForType(field.fieldType),
              color: theme.colorScheme.primary,
            ),
            title: Text(field.name),
            subtitle: Text(
              _subtitleForField(field),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
            onTap: () => _openEditSheet(context, field),
          ),
        );
      },
    );
  }
}
