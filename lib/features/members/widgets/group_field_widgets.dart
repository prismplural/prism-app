// Accessibility: the group card wraps its body in Semantics(container: true)
// so screen readers announce the boundary even when the visible title is
// hidden or empty. Child fields keep their own Semantics from each renderer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_scope.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_renderers.dart';
import 'package:prism_plurality/features/settings/widgets/create_edit_field_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

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
  const _GroupEditorWidget({
    required this.field,
    required this.memberId,
  });

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

          return _GroupCard(
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
    if (renderer == null) return const SizedBox.shrink();
    // Depth-1 hard cap. Write-side validators reject group-in-group, but
    // createFieldFromImport and sync apply tolerate it. Recursing into
    // buildGroupEditor here would stack-overflow on a chain or loop on a
    // cycle. promoteOrphansForRender handles most cases; this guard
    // closes the window before the next stream emission settles.
    if (def!.id == kGroupFieldTypeId) {
      return const SizedBox.shrink();
    }
    return renderer.editorBuilder(context, child, existingValue, memberId);
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
/// The value parameter is unused (groups have no per-member value), but
/// [CustomFieldValue.memberId] is extracted so this widget knows which member's
/// values to watch. Returns [SizedBox.shrink] when all children are empty.
Widget buildGroupDisplay(
  BuildContext context,
  CustomField field,
  CustomFieldValue value,
) {
  return GroupDisplayWidget(field: field, memberId: value.memberId);
}

/// Public factory for use from [CustomFieldsDisplay], which routes group-typed
/// fields directly (no [CustomFieldValue] is available for groups).
Widget buildGroupDisplayForMember(CustomField field, String memberId) {
  return GroupDisplayWidget(field: field, memberId: memberId);
}

/// Read-only display for a Group field. Watches [customFieldsProvider] to
/// find child fields, then [memberCustomFieldValuesProvider] to find their
/// values. Renders children with non-empty values inside [_GroupCard].
/// Returns [SizedBox.shrink] when no children have values.
class GroupDisplayWidget extends ConsumerWidget {
  const GroupDisplayWidget({super.key, required this.field, required this.memberId});

  final CustomField field;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fieldsAsync = ref.watch(customFieldsProvider);
    final valuesAsync = ref.watch(memberCustomFieldValuesProvider(memberId));

    return fieldsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (fields) => valuesAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (values) {
          final children = fields
              .where((f) => f.parentFieldId == field.id)
              .toList()
            ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
          final valuesByFieldId = {
            for (final v in values) v.customFieldId: v,
          };

          final childEntries = <_GroupChildEntry>[];
          for (final child in children) {
            final value = valuesByFieldId[child.id];
            if (value == null || value.value.isEmpty) continue;
            final renderer = rendererFor(
              customFieldTypeRegistry.lookupById(child.fieldTypeId),
            );
            if (renderer == null) continue;
            childEntries.add(
              _GroupChildEntry(
                child: child,
                value: value,
                renderer: renderer,
              ),
            );
          }

          if (childEntries.isEmpty) return const SizedBox.shrink();

          return _GroupCard(
            field: field,
            theme: theme,
            child: CustomFieldDisplayScope(
              labelHandled: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < childEntries.length; i++) ...[
                    if (i > 0) const SizedBox(height: 16),
                    _GroupChildDisplay(entry: childEntries[i]),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GroupChildEntry {
  const _GroupChildEntry({
    required this.child,
    required this.value,
    required this.renderer,
  });

  final CustomField child;
  final CustomFieldValue value;
  final CustomFieldRenderer renderer;
}

/// Compact `Name | Value` for fields whose effective layout is compact;
/// stacked header + body for everything else. Long text skips the parent
/// header — markdown bodies usually carry their own.
///
/// The compact/stacked decision flows through [effectiveDisplayLayout], so
/// in-group rendering matches the standalone choice for the same field.
class _GroupChildDisplay extends StatelessWidget {
  const _GroupChildDisplay({required this.entry});

  final _GroupChildEntry entry;

  static const _headerlessTypeIds = <String>{'long_text'};

  bool get _isHeaderless =>
      _headerlessTypeIds.contains(entry.child.fieldTypeId);

  bool get _isCompact {
    if (_isHeaderless) return false;
    return effectiveDisplayLayout(
          fieldTypeId: entry.child.fieldTypeId,
          typeConfig: entry.child.typeConfig,
        ) ==
        DisplayLayout.compact;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isHeaderless) {
      return entry.renderer.displayBuilder(context, entry.child, entry.value);
    }
    if (_isCompact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              flex: 2,
              fit: FlexFit.tight,
              child: Text(
                entry.child.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              flex: 3,
              fit: FlexFit.tight,
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
                textAlign: TextAlign.start,
                child: entry.renderer.displayBuilder(
                  context,
                  entry.child,
                  entry.value,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          entry.child.name,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        entry.renderer.displayBuilder(context, entry.child, entry.value),
      ],
    );
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

/// Small map from string icon identifiers (stored in [GroupConfig.icon]) to
/// [IconData] values. Extend as new group icon options are added.
///
/// Falls back to [AppIcons.folderOutlined] for unrecognised / null entries.
IconData _iconForGroupConfig(String? iconName) {
  return switch (iconName) {
    'folderOutlined' => AppIcons.folderOutlined,
    'notes' => AppIcons.notes,
    'tuneOutlined' => AppIcons.tuneOutlined,
    'accountTreeOutlined' => AppIcons.accountTreeOutlined,
    _ => AppIcons.folderOutlined, // default + forward-compat
  };
}

/// Header is rendered only when the group has a non-empty name and
/// [GroupConfig.hideTitleOnProfile] is false. The Semantics label always
/// carries something so screen readers announce the boundary either way.
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.field,
    required this.theme,
    required this.child,
  });

  final CustomField field;
  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasName = field.name.trim().isNotEmpty;
    final groupConfig = field.typeConfig as GroupConfig?;
    final hideTitle = groupConfig?.hideTitleOnProfile ?? false;
    final showHeader = hasName && !hideTitle;
    final headerIcon = _iconForGroupConfig(groupConfig?.icon);
    final semanticsLabel =
        hasName ? field.name : l10n.customFieldTypeGroup;

    final headerBgColor = theme.colorScheme.onSurface.withValues(alpha: 0.04);
    final dividerColor = theme.colorScheme.onSurface.withValues(alpha: 0.07);

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: PrismSurface(
        tone: PrismSurfaceTone.subtle,
        padding: EdgeInsets.zero,
        borderRadius: 8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHeader)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: headerBgColor,
                  border: Border(
                    bottom: BorderSide(color: dividerColor, width: 1),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        headerIcon,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          field.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: child,
            ),
          ],
        ),
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
