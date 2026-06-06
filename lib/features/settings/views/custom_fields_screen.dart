import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/views/custom_field_detail_screen.dart';
import 'package:prism_plurality/features/settings/widgets/create_edit_field_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/prism_shapes.dart';
import 'package:prism_plurality/shared/utils/custom_field_type_labels.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/utils/optimistic_list_controller.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/adaptive_detail_surface.dart';
import 'package:prism_plurality/shared/widgets/blur_popup.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Settings screen for managing custom field definitions.
class CustomFieldsScreen extends ConsumerWidget {
  const CustomFieldsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync = ref.watch(topLevelCustomFieldsProvider);
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

class _FieldsList extends ConsumerStatefulWidget {
  const _FieldsList({required this.fields});

  final List<CustomField> fields;

  @override
  ConsumerState<_FieldsList> createState() => _FieldsListState();
}

class _FieldsListState extends ConsumerState<_FieldsList> {
  final OptimisticListController<CustomField, String> _optimisticTopLevel =
      OptimisticListController<CustomField, String>(keyOf: (field) => field.id);
  final Map<String, OptimisticListController<CustomField, String>>
  _optimisticChildren = {};

  @override
  void didUpdateWidget(covariant _FieldsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pruneStaleChildControllers(widget.fields);
  }

  void _pruneStaleChildControllers(List<CustomField> fields) {
    final liveGroupIds = {
      for (final field in fields)
        if (field.fieldTypeId == 'group' && field.parentFieldId == null)
          field.id,
    };
    for (final staleGroupId
        in _optimisticChildren.keys
            .where((id) => !liveGroupIds.contains(id))
            .toList()) {
      _optimisticChildren.remove(staleGroupId);
    }
  }

  void _clearOptimisticAfterBuild(
    OptimisticListController<CustomField, String> controller,
    List<CustomField> current,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.isCurrent(current)) return;
      setState(controller.clear);
    });
  }

  void _persistReorder(
    OptimisticListController<CustomField, String> controller,
    List<CustomField> reordered,
  ) {
    unawaited(
      ref
          .read(customFieldNotifierProvider.notifier)
          .reorderFields(reordered)
          .catchError((Object error, StackTrace _) {
            if (!mounted || !controller.hasCurrentOrder(reordered)) return;
            setState(controller.clear);
            PrismToast.error(
              context,
              message: context.l10n.settingsCustomFieldsError(error.toString()),
            );
          }),
    );
  }

  IconData _iconForField(CustomField field) {
    return customFieldTypeRegistry.lookupById(field.fieldTypeId)?.icon ??
        AppIcons.textFields;
  }

  String _subtitleForField(BuildContext context, CustomField field) {
    final l10n = context.l10n;
    final typeLabel = localizedFieldTypeLabel(l10n, field);
    if (field.fieldType == CustomFieldType.date &&
        field.datePrecision != null) {
      return '$typeLabel • ${field.datePrecision!.localizedLabel(l10n)}';
    }
    return typeLabel;
  }

  void _onReorder(
    OptimisticListController<CustomField, String> controller,
    List<CustomField> topLevel,
    int oldIndex,
    int newIndex,
  ) {
    final reordered = reorderedItems(topLevel, oldIndex, newIndex);
    if (reordered == null) return;
    setState(() => controller.set(reordered));
    // display_order is scoped per parent, so the outer and the nested lists
    // can each reassign 0..n-1 without colliding.
    _persistReorder(controller, reordered);
    Haptics.selection();
  }

  void _onReorderChildren(
    OptimisticListController<CustomField, String> controller,
    List<CustomField> children,
    int oldIndex,
    int newIndex,
  ) {
    final reordered = reorderedItems(children, oldIndex, newIndex);
    if (reordered == null) return;
    setState(() => controller.set(reordered));
    _persistReorder(controller, reordered);
    Haptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fieldIndex = _FieldListIndex.from(widget.fields);
    final providerTopLevel = fieldIndex.topLevelFields;
    final optimisticTopLevel = _optimisticTopLevel.items;
    final topLevel = _optimisticTopLevel.displayItems(providerTopLevel);
    if (_optimisticTopLevel.shouldClearFor(providerTopLevel) &&
        optimisticTopLevel != null) {
      _clearOptimisticAfterBuild(_optimisticTopLevel, optimisticTopLevel);
    }

    return ReorderableListView.builder(
      padding: EdgeInsets.only(top: 8, bottom: NavBarInset.of(context)),
      itemCount: topLevel.length,
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) =>
          _onReorder(_optimisticTopLevel, topLevel, oldIndex, newIndex),
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
        var children = const <CustomField>[];
        void Function(int oldIndex, int newIndex) onReorderChildren = (_, _) {};
        if (isGroup) {
          final providerChildren = fieldIndex.childrenOf(field.id);
          final childController = _optimisticChildren.putIfAbsent(
            field.id,
            () => OptimisticListController<CustomField, String>(
              keyOf: (field) => field.id,
            ),
          );
          final optimisticChildren = childController.items;
          children = childController.displayItems(providerChildren);
          if (childController.shouldClearFor(providerChildren) &&
              optimisticChildren != null) {
            _clearOptimisticAfterBuild(childController, optimisticChildren);
          }
          onReorderChildren = (oldIndex, newIndex) =>
              _onReorderChildren(childController, children, oldIndex, newIndex);
        }

        return _TopLevelFieldItem(
          key: ValueKey(field.id),
          field: field,
          children: children,
          allGroups: fieldIndex.topLevelGroups,
          index: index,
          iconForField: _iconForField,
          subtitleForField: _subtitleForField,
          theme: theme,
          onReorderChildren: onReorderChildren,
        );
      },
    );
  }
}

class _FieldListIndex {
  const _FieldListIndex({
    required this.topLevelFields,
    required this.topLevelGroups,
    required Map<String, List<CustomField>> childrenByParent,
  }) : _childrenByParent = childrenByParent;

  final List<CustomField> topLevelFields;
  final List<CustomField> topLevelGroups;
  final Map<String, List<CustomField>> _childrenByParent;

  static _FieldListIndex from(List<CustomField> fields) {
    final topLevelFields = <CustomField>[];
    final topLevelGroups = <CustomField>[];
    final childrenByParent = <String, List<CustomField>>{};

    for (final field in fields) {
      final parentId = field.parentFieldId;
      if (parentId == null) {
        topLevelFields.add(field);
        if (field.fieldTypeId == 'group') {
          topLevelGroups.add(field);
        }
        continue;
      }

      (childrenByParent[parentId] ??= <CustomField>[]).add(field);
    }

    for (final children in childrenByParent.values) {
      children.sort(_compareFieldOrder);
    }

    return _FieldListIndex(
      topLevelFields: topLevelFields,
      topLevelGroups: topLevelGroups,
      childrenByParent: childrenByParent,
    );
  }

  List<CustomField> childrenOf(String groupId) =>
      _childrenByParent[groupId] ?? const <CustomField>[];
}

int _compareFieldOrder(CustomField a, CustomField b) {
  final byOrder = a.displayOrder.compareTo(b.displayOrder);
  if (byOrder != 0) return byOrder;
  final byCreatedAt = a.createdAt.compareTo(b.createdAt);
  if (byCreatedAt != 0) return byCreatedAt;
  return a.id.compareTo(b.id);
}

class _TopLevelFieldItem extends StatelessWidget {
  const _TopLevelFieldItem({
    super.key,
    required this.field,
    required this.children,
    required this.allGroups,
    required this.index,
    required this.iconForField,
    required this.subtitleForField,
    required this.theme,
    required this.onReorderChildren,
  });

  final CustomField field;
  final List<CustomField> children;
  final List<CustomField> allGroups;
  final int index;
  final IconData Function(CustomField) iconForField;
  final String Function(BuildContext, CustomField) subtitleForField;
  final ThemeData theme;
  final void Function(int oldIndex, int newIndex) onReorderChildren;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldRow(
          field: field,
          allGroups: allGroups,
          index: index,
          iconForField: iconForField,
          subtitleForField: subtitleForField,
          theme: theme,
        ),
        // Nested list — drag handles attach to this inner list; the outer
        // list still owns top-level rows.
        if (children.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: children.length,
              onReorder: onReorderChildren,
              proxyDecorator: (child, _, _) => Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(
                  PrismShapes.of(context).radius(12),
                ),
                child: child,
              ),
              itemBuilder: (context, childIndex) {
                final child = children[childIndex];
                return _FieldRow(
                  key: ValueKey(child.id),
                  field: child,
                  allGroups: allGroups,
                  index: childIndex,
                  iconForField: iconForField,
                  subtitleForField: subtitleForField,
                  theme: theme,
                  isChild: true,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _FieldRow extends ConsumerStatefulWidget {
  const _FieldRow({
    super.key,
    required this.field,
    required this.allGroups,
    required this.index,
    required this.iconForField,
    required this.subtitleForField,
    required this.theme,
    this.isChild = false,
  });

  final CustomField field;
  final List<CustomField> allGroups;
  final int index;
  final IconData Function(CustomField) iconForField;
  final String Function(BuildContext, CustomField) subtitleForField;
  final ThemeData theme;

  /// True when this row is a group child. Children have no drag handle.
  final bool isChild;

  @override
  ConsumerState<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends ConsumerState<_FieldRow> {
  final GlobalKey<BlurPopupAnchorState> _popupKey = GlobalKey();

  void _onLongPress() {
    Haptics.selection();
    _popupKey.currentState?.show();
  }

  /// Groups eligible as a move-into target for [widget.field].
  /// Excludes the field itself (if it is a group) and the field's current parent.
  List<CustomField> _eligibleGroups({bool excludeCurrent = true}) {
    return widget.allGroups.where((g) {
      if (g.id == widget.field.id) return false; // can't move into self
      if (excludeCurrent && g.id == widget.field.parentFieldId) {
        return false; // already inside this group
      }
      return true;
    }).toList();
  }

  /// Unnamed groups need a clickable label in toasts/dialogs too.
  String _displayName(BuildContext context, CustomField f) =>
      f.fieldTypeId == 'group' && f.name.trim().isEmpty
      ? context.l10n.customFieldGroupUntitledFallback
      : f.name;

  Future<void> _moveIntoGroup(
    BuildContext context,
    CustomField targetGroup,
  ) async {
    final movedName = _displayName(context, widget.field);
    final failure = await ref
        .read(customFieldNotifierProvider.notifier)
        .moveFieldToParent(widget.field.id, targetGroup.id);
    if (!context.mounted) return;
    if (failure != null) {
      PrismToast.error(context, message: failure.toString());
      return;
    }
    PrismToast.show(
      context,
      message: '$movedName moved into ${targetGroup.name}',
    );
  }

  Future<void> _moveOutOfGroup(BuildContext context) async {
    final movedName = _displayName(context, widget.field);
    final failure = await ref
        .read(customFieldNotifierProvider.notifier)
        .moveFieldToParent(widget.field.id, null);
    if (!context.mounted) return;
    if (failure != null) {
      PrismToast.error(context, message: failure.toString());
      return;
    }
    PrismToast.show(context, message: '$movedName moved to top level');
  }

  Future<void> _openEditSheet(BuildContext context) async {
    await PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => CreateEditFieldSheet(
        field: widget.field,
        scrollController: scrollController,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final navigator = Navigator.of(context);
    final displayName = _displayName(context, widget.field);
    final deletedToast = context.l10n.settingsCustomFieldsDeletedToast(
      displayName,
    );

    bool?
    deleteChildren; // null = cancel, false = promote, true = delete children

    if (widget.field.fieldTypeId == 'group') {
      deleteChildren = await PrismDialog.show<bool?>(
        context: context,
        title: context.l10n.customFieldGroupDeleteTitle(displayName),
        message: context.l10n.customFieldGroupDeleteMessage,
        actions: [
          PrismButton(
            label: context.l10n.cancel,
            tone: PrismButtonTone.outlined,
            onPressed: () => Navigator.of(context).pop(null),
          ),
          PrismButton(
            label: context.l10n.customFieldGroupDeleteChildren,
            tone: PrismButtonTone.destructive,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          PrismButton(
            label: context.l10n.customFieldGroupPromoteChildren,
            tone: PrismButtonTone.filled,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
        builder: (_) => const SizedBox.shrink(),
      );
      if (deleteChildren == null) return; // user cancelled
    } else {
      final confirmed = await PrismDialog.confirm(
        context: context,
        title: context.l10n.settingsCustomFieldsDeleteTitle,
        message: context.l10n.settingsCustomFieldsDeleteConfirm(displayName),
        confirmLabel: context.l10n.delete,
        destructive: true,
      );
      if (!confirmed) return;
      deleteChildren = false; // non-group, parameter has no effect
    }

    Haptics.heavy();
    await ref
        .read(customFieldNotifierProvider.notifier)
        .deleteField(widget.field.id, deleteChildren: deleteChildren);
    if (context.mounted) {
      PrismToast.show(context, message: deletedToast);
    }
    // If this field was shown nested (isChild), the parent screen handles nav.
    // Navigator.pop is a no-op if there's nothing to pop on this route.
    if (navigator.canPop()) navigator.pop();
  }

  Future<void> _showGroupPicker(
    BuildContext context, {
    required List<CustomField> groups,
    required String title,
    required void Function(CustomField group) onSelected,
  }) async {
    final selected = await PrismDialog.show<CustomField>(
      context: context,
      title: title,
      builder: (ctx) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: groups.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.l10n.customFieldNoEligibleGroups,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: groups.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, index) {
                  final group = groups[index];
                  return Semantics(
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(ctx).pop(group),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(AppIcons.folderOutlined, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                group.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
    if (selected != null) onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final isGroup = field.fieldTypeId == 'group';
    final isNested = field.parentFieldId != null;
    final eligibleForMoveInto = !isGroup
        ? _eligibleGroups(excludeCurrent: true)
        : <CustomField>[];
    final otherGroups = isNested
        ? _eligibleGroups(excludeCurrent: true)
        : <CustomField>[];

    // Menu items for the popup. Edit and Delete always present.
    // Move actions are context-sensitive:
    //   - Groups can't be nested (no Move-into).
    //   - Move-out: only when currently nested.
    //   - Move-into: only for non-groups with at least one eligible group.
    //   - Move-to-another: only when nested AND other groups exist.
    final theme = widget.theme;

    // Groups are the only type allowed to save with an empty name.
    final isPlaceholderName =
        field.name.trim().isEmpty && field.fieldTypeId == 'group';
    final displayName = isPlaceholderName
        ? context.l10n.customFieldGroupUntitledFallback
        : field.name;

    final Widget rowContent = PrismListRow(
      leading: Icon(
        widget.iconForField(field),
        color: theme.colorScheme.primary,
      ),
      title: Text(
        displayName,
        style: isPlaceholderName
            ? theme.textTheme.bodyLarge?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : null,
      ),
      subtitle: Text(
        widget.subtitleForField(context, field),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: Icon(
              AppIcons.dragHandle,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            AppIcons.chevronRightRounded,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ],
      ),
      onTap: () {
        showAdaptiveDetailSurface<void>(
          context: context,
          builder: (_) => CustomFieldDetailScreen(fieldId: field.id),
          route: (context) =>
              context.push(AppRoutePaths.settingsCustomField(field.id)),
        );
      },
    );

    // Wrap in a BlurPopupAnchor (manual trigger) so we can call show() on
    // long-press via _popupKey. The GestureDetector wraps the row content
    // (not the drag handle area, which is scoped to ReorderableDragStartListener).
    return BlurPopupAnchor(
      key: _popupKey,
      trigger: BlurPopupTrigger.manual,
      width: 240,
      maxHeight: 360,
      itemCount: _menuItemCount(
        isGroup: isGroup,
        isNested: isNested,
        hasEligible: eligibleForMoveInto.isNotEmpty,
        hasOtherGroups: otherGroups.isNotEmpty,
      ),
      itemBuilder: (popupContext, index, close) {
        return _buildMenuItem(
          context: context,
          popupContext: popupContext,
          index: index,
          close: close,
          isGroup: isGroup,
          isNested: isNested,
          eligibleGroups: eligibleForMoveInto,
          otherGroups: otherGroups,
        );
      },
      child: GestureDetector(
        onLongPress: _onLongPress,
        behavior: HitTestBehavior.translucent,
        child: rowContent,
      ),
    );
  }

  int _menuItemCount({
    required bool isGroup,
    required bool isNested,
    required bool hasEligible,
    required bool hasOtherGroups,
  }) {
    // Edit + Delete are always present (2).
    int count = 2;
    if (!isGroup && hasEligible) count++; // Move into group
    if (!isGroup && !hasEligible && widget.allGroups.isEmpty) {
      // No groups at all — skip the move-into item entirely
    } else if (!isGroup && !hasEligible) {
      count++; // Show disabled "No groups" hint
    }
    if (isNested) count++; // Move out of group
    if (isNested && hasOtherGroups) count++; // Move to another group
    return count;
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required BuildContext popupContext,
    required int index,
    required VoidCallback close,
    required bool isGroup,
    required bool isNested,
    required List<CustomField> eligibleGroups,
    required List<CustomField> otherGroups,
  }) {
    // Build the ordered list of visible menu items.
    final items = <_MenuItem>[];

    // Edit
    items.add(
      _MenuItem(
        icon: AppIcons.editOutlined,
        label: context.l10n.customFieldMenuEdit,
        enabled: true,
        destructive: false,
        onTap: () {
          close();
          _openEditSheet(context);
        },
      ),
    );

    // Move actions (non-group fields only)
    if (!isGroup) {
      if (eligibleGroups.isNotEmpty) {
        items.add(
          _MenuItem(
            icon: AppIcons.folderOutlined,
            label: context.l10n.customFieldMenuMoveIntoGroup,
            enabled: true,
            destructive: false,
            onTap: () {
              close();
              _showGroupPicker(
                context,
                groups: eligibleGroups,
                title: context.l10n.customFieldMenuMoveIntoGroup,
                onSelected: (g) => _moveIntoGroup(context, g),
              );
            },
          ),
        );
      } else if (widget.allGroups.isNotEmpty) {
        // There are groups but field is already in all of them (edge case) or
        // only the current parent remains — show disabled hint.
        items.add(
          _MenuItem(
            icon: AppIcons.folderOutlined,
            label: context.l10n.customFieldNoEligibleGroups,
            enabled: false,
            destructive: false,
            onTap: null,
          ),
        );
      }
      // If no groups exist at all, omit the move item entirely.
    }

    if (isNested) {
      items.add(
        _MenuItem(
          icon: AppIcons.arrowUpward,
          label: context.l10n.customFieldMenuMoveOutOfGroup,
          enabled: true,
          destructive: false,
          onTap: () {
            close();
            _moveOutOfGroup(context);
          },
        ),
      );

      if (otherGroups.isNotEmpty) {
        items.add(
          _MenuItem(
            icon: AppIcons.arrowForward,
            label: context.l10n.customFieldMenuMoveToAnotherGroup,
            enabled: true,
            destructive: false,
            onTap: () {
              close();
              _showGroupPicker(
                context,
                groups: otherGroups,
                title: context.l10n.customFieldMenuMoveToAnotherGroup,
                onSelected: (g) => _moveIntoGroup(context, g),
              );
            },
          ),
        );
      }
    }

    // Delete (always last)
    items.add(
      _MenuItem(
        icon: AppIcons.deleteOutline,
        label: context.l10n.customFieldMenuDelete,
        enabled: true,
        destructive: true,
        onTap: () {
          close();
          _confirmDelete(context);
        },
      ),
    );

    if (index >= items.length) return const SizedBox.shrink();
    final item = items[index];
    final theme = Theme.of(popupContext);
    final iconColor = !item.enabled
        ? theme.disabledColor
        : item.destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;

    return PrismListRow(
      dense: true,
      enabled: item.enabled,
      destructive: item.destructive,
      leading: Icon(item.icon, size: 20, color: iconColor),
      title: Text(item.label),
      onTap: item.enabled && item.onTap != null ? item.onTap : null,
    );
  }
}

/// Simple data class for a context menu item.
class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.destructive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final bool destructive;
  final VoidCallback? onTap;
}
