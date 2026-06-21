// Accessibility: the group card wraps its body in Semantics(container: true)
// so screen readers announce the boundary even when the visible title is
// hidden or empty. Child fields keep their own Semantics from each renderer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/navigation/member_navigation_branch.dart';
import 'package:prism_plurality/features/members/providers/custom_field_group_profile_preferences.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_display_scope.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_renderers.dart';
import 'package:prism_plurality/features/settings/widgets/create_edit_field_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/animations.dart';
import 'package:prism_plurality/shared/widgets/custom_field_header_icon.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';

int _compareFieldOrder(CustomField a, CustomField b) {
  final byOrder = a.displayOrder.compareTo(b.displayOrder);
  if (byOrder != 0) return byOrder;
  final byCreatedAt = a.createdAt.compareTo(b.createdAt);
  if (byCreatedAt != 0) return byCreatedAt;
  return a.id.compareTo(b.id);
}

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

          final children =
              allFields.where((f) => f.parentFieldId == field.id).toList()
                ..sort(_compareFieldOrder);

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
    return KeyedSubtree(
      key: ValueKey<String>('custom-field-editor-${child.id}'),
      child: renderer.editorBuilder(context, child, existingValue, memberId),
    );
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
Widget buildGroupDisplayForMember(
  CustomField field,
  String memberId, {
  MemberNavigationBranch branch = MemberNavigationBranch.settings,
  String? groupId,
  ValueChanged<String>? onOpenGroupPage,
}) {
  return GroupProfileDisplayWidget(
    field: field,
    memberId: memberId,
    branch: branch,
    groupId: groupId,
    onOpenGroupPage: onOpenGroupPage,
  );
}

class GroupProfileDisplayWidget extends ConsumerWidget {
  const GroupProfileDisplayWidget({
    super.key,
    required this.field,
    required this.memberId,
    required this.branch,
    required this.groupId,
    required this.onOpenGroupPage,
  });

  final CustomField field;
  final String memberId;
  final MemberNavigationBranch branch;
  final String? groupId;
  final ValueChanged<String>? onOpenGroupPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode =
        ref
            .watch(customFieldGroupProfileDisplayModeProvider(field.id))
            .whenOrNull(data: (value) => value) ??
        CustomFieldGroupProfileDisplayMode.inline;

    return switch (mode) {
      CustomFieldGroupProfileDisplayMode.inline => GroupDisplayWidget(
        field: field,
        memberId: memberId,
      ),
      CustomFieldGroupProfileDisplayMode.collapsible =>
        _CollapsibleGroupDisplayWidget(field: field, memberId: memberId),
      CustomFieldGroupProfileDisplayMode.page => _GroupPageRowWidget(
        field: field,
        memberId: memberId,
        branch: branch,
        groupId: groupId,
        onOpenGroupPage: onOpenGroupPage,
      ),
    };
  }
}

/// Read-only display for a Group field. Watches [customFieldsProvider] to
/// find child fields, then [memberCustomFieldValuesProvider] to find their
/// values. Renders children with non-empty values inside [_GroupCard].
/// Returns [SizedBox.shrink] when no children have values.
class GroupDisplayWidget extends ConsumerWidget {
  const GroupDisplayWidget({
    super.key,
    required this.field,
    required this.memberId,
  });

  final CustomField field;
  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return _GroupChildEntriesView(
      field: field,
      memberId: memberId,
      builder: (context, childEntries) {
        if (childEntries.isEmpty) return const SizedBox.shrink();

        return _GroupCard(
          field: field,
          theme: theme,
          child: _GroupChildrenColumn(entries: childEntries),
        );
      },
    );
  }
}

class _CollapsibleGroupDisplayWidget extends ConsumerStatefulWidget {
  const _CollapsibleGroupDisplayWidget({
    required this.field,
    required this.memberId,
  });

  final CustomField field;
  final String memberId;

  @override
  ConsumerState<_CollapsibleGroupDisplayWidget> createState() =>
      _CollapsibleGroupDisplayWidgetState();
}

class _CollapsibleGroupDisplayWidgetState
    extends ConsumerState<_CollapsibleGroupDisplayWidget> {
  bool? _sessionCollapsed;
  CustomFieldGroupCollapseDefaultMode? _lastDefaultMode;

  @override
  void didUpdateWidget(_CollapsibleGroupDisplayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.field.id != widget.field.id ||
        oldWidget.memberId != widget.memberId) {
      _sessionCollapsed = null;
      _lastDefaultMode = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collapsedKey = (memberId: widget.memberId, groupId: widget.field.id);
    final defaultMode =
        ref
            .watch(customFieldGroupCollapseDefaultModeProvider(widget.field.id))
            .whenOrNull(data: (value) => value) ??
        CustomFieldGroupCollapseDefaultMode.lastState;
    if (_lastDefaultMode != defaultMode) {
      _lastDefaultMode = defaultMode;
      _sessionCollapsed = null;
    }

    final rememberedCollapsed =
        defaultMode == CustomFieldGroupCollapseDefaultMode.lastState
        ? ref
                  .watch(customFieldGroupCollapsedProvider(collapsedKey))
                  .whenOrNull(data: (value) => value) ??
              false
        : false;
    final defaultCollapsed = switch (defaultMode) {
      CustomFieldGroupCollapseDefaultMode.open => false,
      CustomFieldGroupCollapseDefaultMode.closed => true,
      CustomFieldGroupCollapseDefaultMode.lastState => rememberedCollapsed,
    };
    final collapsed = _sessionCollapsed ?? defaultCollapsed;

    return _GroupChildEntriesView(
      field: widget.field,
      memberId: widget.memberId,
      builder: (context, childEntries) {
        if (childEntries.isEmpty) return const SizedBox.shrink();
        return _GroupCard(
          field: widget.field,
          theme: theme,
          expanded: !collapsed,
          onToggle: () {
            final nextCollapsed = !collapsed;
            if (defaultMode == CustomFieldGroupCollapseDefaultMode.lastState) {
              ref
                  .read(
                    customFieldGroupCollapsedProvider(collapsedKey).notifier,
                  )
                  .setCollapsed(nextCollapsed);
            } else {
              setState(() => _sessionCollapsed = nextCollapsed);
            }
          },
          child: _GroupChildrenColumn(entries: childEntries),
        );
      },
    );
  }
}

class _GroupPageRowWidget extends StatelessWidget {
  const _GroupPageRowWidget({
    required this.field,
    required this.memberId,
    required this.branch,
    required this.groupId,
    required this.onOpenGroupPage,
  });

  final CustomField field;
  final String memberId;
  final MemberNavigationBranch branch;
  final String? groupId;
  final ValueChanged<String>? onOpenGroupPage;

  @override
  Widget build(BuildContext context) {
    return _GroupChildEntriesView(
      field: field,
      memberId: memberId,
      builder: (context, childEntries) {
        if (childEntries.isEmpty) return const SizedBox.shrink();
        final router = GoRouter.maybeOf(context);
        final path = branch.memberCustomFieldGroupPath(
          memberId,
          field.id,
          groupId: groupId,
        );
        final openInPane = onOpenGroupPage;
        return SizedBox(
          width: double.infinity,
          child: PrismSurface(
            padding: EdgeInsets.zero,
            tone: PrismSurfaceTone.subtle,
            child: PrismListRow(
              leading: _GroupPageLeadingIcon(field: field),
              title: Text(
                field.name.trim().isEmpty
                    ? context.l10n.customFieldGroupUntitledFallback
                    : field.name,
              ),
              showChevron: true,
              onTap: openInPane != null
                  ? () => openInPane(field.id)
                  : router == null
                  ? null
                  : () => router.push(path),
            ),
          ),
        );
      },
    );
  }
}

class _GroupPageLeadingIcon extends StatelessWidget {
  const _GroupPageLeadingIcon({required this.field});

  final CustomField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return SizedBox.square(
      dimension: 32,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
        ),
        child: Center(
          child: hasRenderableCustomFieldHeaderIcon(field)
              ? CustomFieldHeaderIconView(field: field, size: 18, color: color)
              : Icon(AppIcons.folderOutlined, size: 18, color: color),
        ),
      ),
    );
  }
}

class _GroupChildEntriesView extends ConsumerWidget {
  const _GroupChildEntriesView({
    required this.field,
    required this.memberId,
    required this.builder,
  });

  final CustomField field;
  final String memberId;
  final Widget Function(BuildContext context, List<_GroupChildEntry> entries)
  builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync = ref.watch(customFieldsProvider);
    final valuesAsync = ref.watch(memberCustomFieldValuesProvider(memberId));

    return fieldsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (fields) => valuesAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (values) => builder(
          context,
          _groupChildEntries(
            fields: fields,
            values: values,
            parentFieldId: field.id,
          ),
        ),
      ),
    );
  }
}

List<_GroupChildEntry> _groupChildEntries({
  required List<CustomField> fields,
  required List<CustomFieldValue> values,
  required String parentFieldId,
}) {
  final children =
      fields.where((f) => f.parentFieldId == parentFieldId).toList()
        ..sort(_compareFieldOrder);
  final valuesByFieldId = {for (final v in values) v.customFieldId: v};

  final childEntries = <_GroupChildEntry>[];
  for (final child in children) {
    final value = valuesByFieldId[child.id];
    if (value == null || value.value.isEmpty) continue;
    final renderer = rendererFor(
      customFieldTypeRegistry.lookupById(child.fieldTypeId),
    );
    if (renderer == null) continue;
    childEntries.add(
      _GroupChildEntry(child: child, value: value, renderer: renderer),
    );
  }
  return childEntries;
}

class _GroupChildrenColumn extends StatelessWidget {
  const _GroupChildrenColumn({required this.entries});

  final List<_GroupChildEntry> entries;

  @override
  Widget build(BuildContext context) {
    return CustomFieldDisplayScope(
      labelHandled: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _GroupChildDisplay(entry: entries[i]),
          ],
        ],
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
/// stacked header + body for everything else.
class _GroupChildDisplay extends StatelessWidget {
  const _GroupChildDisplay({required this.entry});

  final _GroupChildEntry entry;

  bool get _isChoice => entry.child.fieldTypeId == 'choice';

  bool get _isLongText => entry.child.fieldTypeId == 'long_text';

  /// Per-field opt-out: the child's own `hideTitleOnProfile` suppresses its
  /// label inside the group, independent of the parent group's toggle.
  bool get _hideTitle => effectiveHideTitleOnProfile(entry.child.typeConfig);

  bool get _isCompact {
    if (_isChoice) {
      final config = entry.child.typeConfig;
      return config is ChoiceConfig &&
          config.displayLayout == DisplayLayout.compact;
    }
    if (_isLongText) return false;
    return effectiveDisplayLayout(
          fieldTypeId: entry.child.fieldTypeId,
          typeConfig: entry.child.typeConfig,
        ) ==
        DisplayLayout.compact;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_hideTitle) {
      // Value-only: the surrounding group card supplies the visual container,
      // so no per-child icon affordance is needed. Wrap in Semantics so the
      // child's name is still announced to screen readers.
      return Semantics(
        label: entry.child.name,
        child: entry.renderer.displayBuilder(context, entry.child, entry.value),
      );
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
              child: CustomFieldHeaderLabel(
                field: entry.child,
                iconSize: 16,
                iconColor: theme.colorScheme.primary,
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
                child: entry.renderer.compactBuilder(
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
        CustomFieldHeaderLabel(
          field: entry.child,
          iconSize: 16,
          iconColor: theme.colorScheme.primary,
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

/// Header is rendered only when the group has a non-empty name and
/// [GroupConfig.hideTitleOnProfile] is false. The Semantics label always
/// carries something so screen readers announce the boundary either way.
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.field,
    required this.theme,
    required this.child,
    this.expanded,
    this.onToggle,
  });

  final CustomField field;
  final ThemeData theme;
  final Widget child;
  final bool? expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasName = field.name.trim().isNotEmpty;
    final groupConfig = field.typeConfig as GroupConfig?;
    final hideTitle = groupConfig?.hideTitleOnProfile ?? false;
    final isCollapsible = expanded != null && onToggle != null;
    final showHeader = hasName && (!hideTitle || isCollapsible);
    final showBody = expanded ?? true;
    final semanticsLabel = hasName ? field.name : l10n.customFieldTypeGroup;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final bodyAnimationDuration = reduceMotion
        ? Duration.zero
        : showBody
        ? const Duration(milliseconds: 260)
        : Anim.md;
    final headerAnimationDuration = reduceMotion
        ? Duration.zero
        : showBody
        ? Anim.lg
        : Anim.sm;
    final bodyAnimationCurve = showBody
        ? Curves.easeOutCubic
        : Curves.easeInCubic;
    final headerAnimationCurve = showBody
        ? Curves.easeInOutCubic
        : Curves.easeInCubic;

    final headerBgColor = theme.colorScheme.onSurface.withValues(alpha: 0.04);
    final dividerColor = theme.colorScheme.onSurface.withValues(alpha: 0.07);
    final body = showBody
        ? Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: child,
          )
        : const SizedBox(width: double.infinity);

    final card = Semantics(
      container: true,
      label: semanticsLabel,
      child: PrismSurface(
        tone: PrismSurfaceTone.subtle,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showHeader)
              Semantics(
                button: isCollapsible ? true : null,
                expanded: isCollapsible ? expanded : null,
                label: isCollapsible ? semanticsLabel : null,
                child: GestureDetector(
                  behavior: isCollapsible
                      ? HitTestBehavior.opaque
                      : HitTestBehavior.deferToChild,
                  onTap: isCollapsible ? onToggle : null,
                  child: AnimatedContainer(
                    width: double.infinity,
                    duration: headerAnimationDuration,
                    curve: headerAnimationCurve,
                    decoration: BoxDecoration(
                      color: showBody ? headerBgColor : Colors.transparent,
                      border: Border(
                        bottom: BorderSide(
                          color: showBody ? dividerColor : Colors.transparent,
                          width: showBody ? 1 : 0,
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: CustomFieldHeaderLabel(
                              field: field,
                              iconSize: 16,
                              iconColor: theme.colorScheme.primary,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (isCollapsible) ...[
                            const SizedBox(width: 8),
                            SizedBox.square(
                              dimension: 24,
                              child: AnimatedRotation(
                                turns: expanded! ? 0.5 : 0,
                                duration: bodyAnimationDuration,
                                curve: bodyAnimationCurve,
                                child: Icon(
                                  AppIcons.expandMore,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (reduceMotion)
              body
            else
              AnimatedSize(
                duration: bodyAnimationDuration,
                curve: bodyAnimationCurve,
                alignment: Alignment.topCenter,
                child: body,
              ),
          ],
        ),
      ),
    );
    return SizedBox(width: double.infinity, child: card);
  }
}

/// Empty-state button shown inside an empty group editor.
class _EmptyGroupButton extends StatelessWidget {
  const _EmptyGroupButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PrismButton(
      label: label,
      icon: AppIcons.add,
      onPressed: onTap,
      density: PrismControlDensity.compact,
      tone: PrismButtonTone.subtle,
    );
  }
}
