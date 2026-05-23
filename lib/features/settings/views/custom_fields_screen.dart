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

  IconData _iconForType(CustomFieldType type) => switch (type) {
    CustomFieldType.text => AppIcons.textFields,
    CustomFieldType.longText => AppIcons.notes,
    CustomFieldType.color => AppIcons.palette,
    CustomFieldType.date => AppIcons.calendarToday,
  };

  String _subtitleForField(BuildContext context, CustomField field) {
    if (field.fieldType == CustomFieldType.date &&
        field.datePrecision != null) {
      return '${field.fieldType.localizedLabel(context.l10n)} \u2022 '
          '${field.datePrecision!.localizedLabel(context.l10n)}';
    }
    return field.fieldType.localizedLabel(context.l10n);
  }

  void _onReorder(WidgetRef ref, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final reordered = List<CustomField>.from(fields);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    ref.read(customFieldNotifierProvider.notifier).reorderFields(reordered);
    Haptics.selection();
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
            borderRadius: BorderRadius.circular(
              PrismShapes.of(context).radius(12),
            ),
            child: child,
          ),
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final field = fields[index];
        return PrismListRow(
          key: ValueKey(field.id),
          leading: Icon(
            _iconForType(field.fieldType),
            color: theme.colorScheme.primary,
          ),
          title: Text(field.name),
          subtitle: Text(
            _subtitleForField(context, field),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Icon(
                  AppIcons.dragHandle,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                AppIcons.chevronRightRounded,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
              ),
            ],
          ),
          onTap: () =>
              context.push(AppRoutePaths.settingsCustomField(field.id)),
        );
      },
    );
  }
}
