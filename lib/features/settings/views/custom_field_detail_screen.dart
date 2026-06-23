import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/custom_fields/custom_field_type_registry.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/choice_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/members_batch_provider.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/members/widgets/scale_field_widgets.dart';
import 'package:prism_plurality/features/members/widgets/slider_field_widgets.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/services/field_template_export_service.dart';
import 'package:prism_plurality/features/settings/views/custom_field_group_delete_actions.dart';
import 'package:prism_plurality/features/settings/widgets/create_edit_field_sheet.dart';
import 'package:prism_plurality/features/settings/widgets/share_template_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/custom_field_type_labels.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/utils/optimistic_list_controller.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/custom_field_header_icon.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/member_chip.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_inline_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_list_row.dart';
import 'package:prism_plurality/shared/widgets/prism_loading_state.dart';
import 'package:prism_plurality/shared/widgets/prism_page_scaffold.dart';
import 'package:prism_plurality/shared/widgets/prism_popup_menu.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';
import 'package:prism_plurality/shared/widgets/prism_sheet.dart';
import 'package:prism_plurality/shared/widgets/prism_surface.dart';
import 'package:prism_plurality/shared/widgets/prism_toast.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';
import 'package:prism_plurality/shared/widgets/prism_chip.dart';

class CustomFieldDetailScreen extends ConsumerWidget {
  const CustomFieldDetailScreen({super.key, required this.fieldId});

  final String fieldId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldAsync = ref.watch(customFieldByIdProvider(fieldId));

    return fieldAsync.when(
      loading: () => PrismPageScaffold(
        topBar: PrismTopBar(
          title: context.l10n.settingsCustomFieldsTitle,
          showBackButton: true,
        ),
        body: const PrismLoadingState(),
      ),
      error: (e, _) => PrismPageScaffold(
        topBar: PrismTopBar(
          title: context.l10n.settingsCustomFieldsTitle,
          showBackButton: true,
        ),
        body: Center(
          child: Text(context.l10n.settingsCustomFieldsError(e.toString())),
        ),
      ),
      data: (field) {
        if (field == null) {
          return PrismPageScaffold(
            topBar: PrismTopBar(
              title: context.l10n.settingsCustomFieldsTitle,
              showBackButton: true,
            ),
            body: Center(child: Text(context.l10n.settingsCustomFieldNotFound)),
          );
        }
        return _CustomFieldDetailBody(field: field);
      },
    );
  }
}

class _CustomFieldDetailBody extends ConsumerStatefulWidget {
  const _CustomFieldDetailBody({required this.field});

  final CustomField field;

  @override
  ConsumerState<_CustomFieldDetailBody> createState() =>
      _CustomFieldDetailBodyState();
}

/// Enum used as menu value for the overflow action menu.
enum _MoveAction { moveIntoGroup, moveOutOfGroup, moveToAnotherGroup }

class _CustomFieldDetailBodyState
    extends ConsumerState<_CustomFieldDetailBody> {
  CustomField get field => widget.field;

  /// All top-level group fields in the system.
  List<CustomField> _allGroups(List<CustomField> allFields) => allFields
      .where((f) => f.fieldTypeId == 'group' && f.parentFieldId == null)
      .toList();

  List<CustomField> _eligibleGroups(List<CustomField> allFields) {
    return _allGroups(allFields).where((g) {
      if (g.id == field.id) return false;
      if (g.id == field.parentFieldId) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasHeaderIcon = hasRenderableCustomFieldHeaderIcon(field);
    final allFieldsAsync = ref.watch(topLevelCustomFieldsProvider);
    final allFields = allFieldsAsync.value ?? <CustomField>[];
    final isGroup = field.fieldTypeId == 'group';
    final isNested = field.parentFieldId != null;
    final eligible = !isGroup ? _eligibleGroups(allFields) : <CustomField>[];
    final otherGroups = isNested ? _eligibleGroups(allFields) : <CustomField>[];
    final parentGroup = isNested
        ? allFields.where((f) => f.id == field.parentFieldId).firstOrNull
        : null;

    // Build the overflow menu items for move actions.
    // Edit and Delete stay as direct visible app bar actions.
    // Groups can't be nested, so they never get move items.
    final moveItems = <PrismMenuItem<_MoveAction>>[];
    if (!isGroup) {
      if (eligible.isNotEmpty) {
        moveItems.add(
          PrismMenuItem(
            value: _MoveAction.moveIntoGroup,
            label: context.l10n.customFieldMenuMoveIntoGroup,
            icon: AppIcons.folderOutlined,
          ),
        );
      } else if (_allGroups(allFields).isNotEmpty) {
        moveItems.add(
          PrismMenuItem(
            value: _MoveAction.moveIntoGroup,
            label: context.l10n.customFieldNoEligibleGroups,
            icon: AppIcons.folderOutlined,
            enabled: false,
          ),
        );
      }
    }
    if (isNested) {
      moveItems.add(
        PrismMenuItem(
          value: _MoveAction.moveOutOfGroup,
          label: context.l10n.customFieldMenuMoveOutOfGroup,
          icon: AppIcons.arrowUpward,
        ),
      );
      if (otherGroups.isNotEmpty) {
        moveItems.add(
          PrismMenuItem(
            value: _MoveAction.moveToAnotherGroup,
            label: context.l10n.customFieldMenuMoveToAnotherGroup,
            icon: AppIcons.arrowForward,
          ),
        );
      }
    }

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: true,
        actions: [
          PrismTopBarAction(
            icon: AppIcons.share,
            tooltip: context.l10n.customFieldMenuShareAsTemplate,
            onPressed: () => _shareAsTemplate(context),
          ),
          PrismTopBarAction(
            icon: AppIcons.editOutlined,
            tooltip: context.l10n.edit,
            onPressed: () => _openEditSheet(context),
          ),
          PrismTopBarAction(
            icon: AppIcons.deleteOutline,
            tooltip: context.l10n.delete,
            onPressed: () => _confirmDelete(context),
          ),
          // Only show the overflow menu when there are move actions available.
          if (moveItems.isNotEmpty)
            PrismPopupMenu<_MoveAction>(
              items: moveItems,
              width: 260,
              onSelected: (action) => _handleMoveAction(
                context,
                action: action,
                allFields: allFields,
                eligible: eligible,
                otherGroups: otherGroups,
              ),
            ),
        ],
      ),
      bodyPadding: EdgeInsets.zero,
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            sliver: SliverList.list(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasHeaderIcon) ...[
                      CustomFieldHeaderIconView(
                        field: field,
                        color: theme.colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName(context, field),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontStyle: _isPlaceholderName(field)
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              color: _isPlaceholderName(field)
                                  ? theme.colorScheme.onSurfaceVariant
                                  : null,
                            ),
                          ),
                          // "Inside: {group}" badge when nested.
                          if (parentGroup != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  AppIcons.folderOutlined,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  context.l10n.customFieldDetailInsideGroup(
                                    parentGroup.name,
                                  ),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                PrismSectionCard(
                  child: Column(
                    children: [
                      _MetadataRow(
                        label: context.l10n.settingsCreateEditFieldTypeHeading,
                        value: _labelForField(context, field),
                      ),
                      if (field.fieldType == CustomFieldType.date &&
                          field.datePrecision != null) ...[
                        const Divider(height: 1),
                        _MetadataRow(
                          label: context
                              .l10n
                              .settingsCreateEditFieldDatePrecisionHeading,
                          value: field.datePrecision!.localizedLabel(
                            context.l10n,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
          // Groups have no per-member value, so "Filled in by N" is empty
          // by definition — list the children instead.
          if (isGroup)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver: SliverToBoxAdapter(
                child: _GroupContentsSection(group: field),
              ),
            )
          else
            _FilledInSection(field: field),
          SliverPadding(
            padding: EdgeInsets.only(bottom: NavBarInset.of(context)),
          ),
        ],
      ),
    );
  }

  void _openEditSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (context, scrollController) => CreateEditFieldSheet(
        field: field,
        scrollController: scrollController,
      ),
    );
  }

  Future<void> _shareAsTemplate(BuildContext context) async {
    final service = ref.read(fieldTemplateExportServiceProvider);
    try {
      final template = field.fieldTypeId == 'group'
          ? await service.buildTemplateForGroup(field.id)
          : await service.buildTemplateForField(field.id);
      if (!context.mounted) return;
      await ShareTemplateSheet.show(context, template: template);
    } catch (e) {
      // The field/group may have been deleted between tap and read.
      if (context.mounted) {
        PrismToast.error(
          context,
          message: context.l10n.settingsCustomFieldsError(e.toString()),
        );
      }
    }
  }

  Future<void> _handleMoveAction(
    BuildContext context, {
    required _MoveAction action,
    required List<CustomField> allFields,
    required List<CustomField> eligible,
    required List<CustomField> otherGroups,
  }) async {
    switch (action) {
      case _MoveAction.moveIntoGroup:
        await _showGroupPicker(
          context,
          groups: eligible,
          title: context.l10n.customFieldMenuMoveIntoGroup,
          onSelected: (g) => _moveIntoGroup(context, g),
        );
      case _MoveAction.moveOutOfGroup:
        await _moveOutOfGroup(context);
      case _MoveAction.moveToAnotherGroup:
        await _showGroupPicker(
          context,
          groups: otherGroups,
          title: context.l10n.customFieldMenuMoveToAnotherGroup,
          onSelected: (g) => _moveIntoGroup(context, g),
        );
    }
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

  Future<void> _moveIntoGroup(
    BuildContext context,
    CustomField targetGroup,
  ) async {
    final movedName = _displayName(context, field);
    final failure = await ref
        .read(customFieldNotifierProvider.notifier)
        .moveFieldToParent(field.id, targetGroup.id);
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
    final movedName = _displayName(context, field);
    final failure = await ref
        .read(customFieldNotifierProvider.notifier)
        .moveFieldToParent(field.id, null);
    if (!context.mounted) return;
    if (failure != null) {
      PrismToast.error(context, message: failure.toString());
      return;
    }
    PrismToast.show(context, message: '$movedName moved to top level');
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final navigator = Navigator.of(context);
    final router = GoRouter.maybeOf(context);
    final displayName = _displayName(context, field);
    final deletedToast = context.l10n.settingsCustomFieldsDeletedToast(
      displayName,
    );

    bool? deleteChildren;

    if (field.fieldTypeId == 'group') {
      deleteChildren = await PrismDialog.show<bool?>(
        context: context,
        title: context.l10n.customFieldGroupDeleteTitle(displayName),
        message: context.l10n.customFieldGroupDeleteMessage,
        actions: buildCustomFieldGroupDeleteActions(context),
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
        .deleteField(field.id, deleteChildren: deleteChildren);
    if (context.mounted) {
      PrismToast.show(context, message: deletedToast);
    }
    if (router != null) {
      router.go(AppRoutePaths.settingsCustomFields);
    } else if (navigator.canPop()) {
      navigator.pop();
    }
  }

  bool _isPlaceholderName(CustomField field) =>
      field.fieldTypeId == 'group' && field.name.trim().isEmpty;

  String _displayName(BuildContext context, CustomField field) =>
      _isPlaceholderName(field)
      ? context.l10n.customFieldGroupUntitledFallback
      : field.name;

  String _labelForField(BuildContext context, CustomField field) =>
      localizedFieldTypeLabel(
        context.l10n,
        field,
        memberTypeLabel: watchTerminology(context, ref).singular,
      );
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilledInSection extends ConsumerWidget {
  const _FilledInSection({required this.field});

  final CustomField field;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valuesAsync = ref.watch(customFieldValuesForFieldProvider(field.id));

    return valuesAsync.when(
      loading: () => const SliverToBoxAdapter(child: PrismLoadingState()),
      error: (e, _) => SliverToBoxAdapter(
        child: Center(
          child: Text(context.l10n.settingsCustomFieldsError(e.toString())),
        ),
      ),
      data: (values) {
        final memberIds = {
          for (final value in values)
            if (value.value.trim().isNotEmpty &&
                value.memberId != unknownSentinelMemberId)
              value.memberId,
          if (field.fieldTypeId == 'member')
            for (final value in values)
              if (value.value.trim().isNotEmpty &&
                  value.memberId != unknownSentinelMemberId)
                ..._parseMemberReferenceIds(field, value.value),
        };
        final membersAsync = ref.watch(
          membersByIdsListProvider(memberIdsKey(memberIds)),
        );

        return membersAsync.when(
          loading: () => const SliverToBoxAdapter(child: PrismLoadingState()),
          error: (e, _) => SliverToBoxAdapter(
            child: Center(
              child: Text(context.l10n.settingsCustomFieldsError(e.toString())),
            ),
          ),
          data: (membersById) => _FilledInContent(
            field: field,
            values: values,
            membersById: membersById,
          ),
        );
      },
    );
  }
}

class _FilledInContent extends ConsumerWidget {
  const _FilledInContent({
    required this.field,
    required this.values,
    required this.membersById,
  });

  final CustomField field;
  final List<CustomFieldValue> values;
  final Map<String, Member> membersById;

  static const _longShortTextValueLength = 80;
  static const _longShortTextValueCount = 2;
  static const _longShortTextValueRatio = 0.5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);
    final preferDisplayName = ref.watch(memberNamePreferDisplayProvider);
    final entries = [
      for (final value in values)
        if (value.value.trim().isNotEmpty &&
            membersById[value.memberId] != null)
          _FilledValueEntry(member: membersById[value.memberId]!, value: value),
    ];
    final showLengthHint = _shouldShowLongTextHint(entries);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverList.list(
            children: [
              Row(
                children: [
                  Icon(
                    AppIcons.checkCircleOutline,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.settingsCustomFieldFilledInHeading,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.settingsCustomFieldFilledInCount(
                  entries.length,
                  terms.singularLower,
                  terms.pluralLower,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (showLengthHint) ...[
                const _ShortTextLengthHint(),
                const SizedBox(height: 12),
              ],
              if (entries.isEmpty)
                EmptyState(
                  icon: Icon(AppIcons.tuneOutlined),
                  title: context.l10n.settingsCustomFieldNoValuesTitle,
                  subtitle: context.l10n.settingsCustomFieldNoValuesSubtitle(
                    terms.pluralLower,
                  ),
                ),
            ],
          ),
          if (entries.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == entries.length - 1 ? 0 : 8,
                  ),
                  child: PrismSectionCard(
                    padding: EdgeInsets.zero,
                    child: _FilledValueRow(
                      field: field,
                      entry: entries[index],
                      membersById: membersById,
                      preferDisplayName: preferDisplayName,
                    ),
                  ),
                );
              }, childCount: entries.length),
            ),
        ],
      ),
    );
  }

  bool _shouldShowLongTextHint(List<_FilledValueEntry> entries) {
    if (field.fieldType != CustomFieldType.text || entries.isEmpty) {
      return false;
    }

    final longValueCount = entries
        .where((entry) => _looksLongForShortText(entry.value.value))
        .length;
    return longValueCount >= _longShortTextValueCount &&
        longValueCount / entries.length >= _longShortTextValueRatio;
  }

  bool _looksLongForShortText(String raw) {
    final value = raw.trim();
    return value.contains('\n') || value.length >= _longShortTextValueLength;
  }
}

class _ShortTextLengthHint extends StatelessWidget {
  const _ShortTextLengthHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PrismSurface(
      tone: PrismSurfaceTone.subtle,
      accentColor: AppColors.warning,
      borderRadius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.infoOutline, color: AppColors.warning, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.settingsCustomFieldLongShortTextHint(
                CustomFieldType.longText.localizedLabel(context.l10n),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilledValueEntry {
  const _FilledValueEntry({required this.member, required this.value});

  final Member member;
  final CustomFieldValue value;
}

class _FilledValueRow extends StatelessWidget {
  const _FilledValueRow({
    required this.field,
    required this.entry,
    required this.membersById,
    required this.preferDisplayName,
  });

  final CustomField field;
  final _FilledValueEntry entry;
  final Map<String, Member> membersById;
  final bool preferDisplayName;

  @override
  Widget build(BuildContext context) {
    final member = entry.member;
    final memberName = member.effectiveName(
      preferDisplayName: preferDisplayName,
    );
    final formattedValue = _formatValueForField(
      context,
      field,
      entry.value.value,
      ownerMember: member,
      membersById: membersById,
      preferDisplayName: preferDisplayName,
    );

    return Semantics(
      label: context.l10n.settingsCustomFieldValueSemantics(
        field.name,
        memberName,
        formattedValue,
      ),
      child: PrismListRow(
        leading: MemberAvatar(
          avatarImageData: member.avatarImageData,
          memberId: member.id,
          deferAvatarLookup: true,
          memberName: memberName,
          emoji: member.emoji,
          customColorEnabled: member.customColorHex != null,
          customColorHex: member.customColorHex,
          size: 36,
        ),
        title: Text(memberName),
        subtitle: _ValuePreview(
          field: field,
          value: entry.value,
          ownerMember: member,
          membersById: membersById,
          preferDisplayName: preferDisplayName,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

class _ValuePreview extends StatelessWidget {
  const _ValuePreview({
    required this.field,
    required this.value,
    required this.ownerMember,
    required this.membersById,
    required this.preferDisplayName,
  });

  static const _previewCharacterLimit = 220;
  static const _previewLineLimit = 4;

  final CustomField field;
  final CustomFieldValue value;
  final Member ownerMember;
  final Map<String, Member> membersById;
  final bool preferDisplayName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rawValue = value.value;

    if (field.fieldTypeId == 'slider') {
      return buildSliderCompact(context, field, value, trackWidth: 140);
    }
    if (field.fieldTypeId == 'scale') {
      return buildScaleMini(context, field, value);
    }
    if (field.fieldTypeId == 'member') {
      return _MemberValuePreview(
        field: field,
        rawValue: rawValue,
        ownerMember: ownerMember,
        membersById: membersById,
        preferDisplayName: preferDisplayName,
      );
    }
    if (field.fieldType == CustomFieldType.color) {
      return _ColorValue(value: rawValue);
    }

    final formattedValue = _formatValueForField(
      context,
      field,
      rawValue,
      ownerMember: ownerMember,
      membersById: membersById,
      preferDisplayName: preferDisplayName,
    );
    final preview = _buildPreview(formattedValue);
    final isTruncated = preview != formattedValue.trimRight();
    return Text(
      isTruncated ? '$preview...' : formattedValue,
      maxLines: field.fieldType == CustomFieldType.longText ? 4 : 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface,
        height: 1.35,
      ),
    );
  }

  String _buildPreview(String raw) {
    final normalized = raw.trimRight();
    final lines = normalized.split('\n');
    var preview = lines.length > _previewLineLimit
        ? lines.take(_previewLineLimit).join('\n')
        : normalized;

    if (preview.length > _previewCharacterLimit) {
      preview = preview.substring(0, _previewCharacterLimit);
      final lastWhitespace = preview.lastIndexOf(RegExp(r'\s'));
      if (lastWhitespace > _previewCharacterLimit * 0.65) {
        preview = preview.substring(0, lastWhitespace);
      }
    }

    return preview.trimRight();
  }
}

class _MemberValuePreview extends StatelessWidget {
  const _MemberValuePreview({
    required this.field,
    required this.rawValue,
    required this.ownerMember,
    required this.membersById,
    required this.preferDisplayName,
  });

  final CustomField field;
  final String rawValue;
  final Member ownerMember;
  final Map<String, Member> membersById;
  final bool preferDisplayName;

  @override
  Widget build(BuildContext context) {
    final refs = _memberReferenceSummaries(
      context,
      field,
      rawValue,
      ownerMember: ownerMember,
      membersById: membersById,
      preferDisplayName: preferDisplayName,
    );
    if (refs.isEmpty) {
      refs.add(
        _MemberReferenceSummary(
          id: null,
          label: _unavailableMemberLabel(context),
          member: null,
          isUnavailable: true,
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final ref in refs) _MemberReferenceChip(summary: ref)],
    );
  }
}

class _MemberReferenceChip extends StatelessWidget {
  const _MemberReferenceChip({required this.summary});

  final _MemberReferenceSummary summary;

  @override
  Widget build(BuildContext context) {
    final member = summary.member;
    if (member != null) {
      return MemberChip(
        member: member,
        resolvedName: summary.label,
        style: MemberChipStyle.inline,
        avatarSize: 18,
        labelMaxLines: 1,
      );
    }

    return PrismChip(
      label: summary.label,
      selected: !summary.isUnavailable,
      onTap: null,
      avatar: member != null
          ? MemberAvatar(
              memberId: member.id,
              memberName: summary.label,
              emoji: member.emoji,
              avatarImageData: member.avatarImageData,
              customColorEnabled: member.customColorEnabled,
              customColorHex: member.customColorHex,
              size: 18,
              deferAvatarLookup: true,
            )
          : Icon(AppIcons.personOffOutlined, size: 18),
      variant: summary.isUnavailable
          ? PrismChipVariant.filled
          : PrismChipVariant.inline,
    );
  }
}

class _ColorValue extends StatelessWidget {
  const _ColorValue({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color? color;
    try {
      color = AppColors.fromHex(value);
    } catch (_) {
      color = null;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (color != null) ...[
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

String _formatValueForField(
  BuildContext context,
  CustomField field,
  String raw, {
  Member? ownerMember,
  Map<String, Member> membersById = const <String, Member>{},
  bool preferDisplayName = true,
}) {
  if (field.fieldTypeId == 'member') {
    return _formatMemberValue(
      context,
      field,
      raw,
      ownerMember: ownerMember,
      membersById: membersById,
      preferDisplayName: preferDisplayName,
    );
  }
  return switch (field.fieldType) {
    CustomFieldType.date => _formatDateValue(context, raw, field.datePrecision),
    CustomFieldType.choice => _formatChoiceValue(context, field, raw),
    CustomFieldType.text ||
    CustomFieldType.longText ||
    CustomFieldType.color => raw,
  };
}

String _formatMemberValue(
  BuildContext context,
  CustomField field,
  String raw, {
  Member? ownerMember,
  Map<String, Member> membersById = const <String, Member>{},
  bool preferDisplayName = true,
}) {
  final refs = _memberReferenceSummaries(
    context,
    field,
    raw,
    ownerMember: ownerMember,
    membersById: membersById,
    preferDisplayName: preferDisplayName,
  );
  if (refs.isEmpty) return _unavailableMemberLabel(context);
  return refs.map((ref) => ref.label).join(', ');
}

class _MemberReferenceSummary {
  const _MemberReferenceSummary({
    required this.id,
    required this.label,
    required this.member,
    required this.isUnavailable,
  });

  final String? id;
  final String label;
  final Member? member;
  final bool isUnavailable;
}

List<_MemberReferenceSummary> _memberReferenceSummaries(
  BuildContext context,
  CustomField field,
  String raw, {
  Member? ownerMember,
  Map<String, Member> membersById = const <String, Member>{},
  bool preferDisplayName = true,
}) {
  final ids = _parseMemberReferenceIds(field, raw);
  return [
    for (final id in ids)
      if (membersById[id] case final member?)
        _MemberReferenceSummary(
          id: id,
          label: member.effectiveName(preferDisplayName: preferDisplayName),
          member: member,
          isUnavailable: false,
        )
      else if (ownerMember != null && id == ownerMember.id)
        _MemberReferenceSummary(
          id: id,
          label: ownerMember.effectiveName(preferDisplayName: preferDisplayName),
          member: ownerMember,
          isUnavailable: false,
        )
      else
        _MemberReferenceSummary(
          id: id,
          label: _unavailableMemberLabel(context),
          member: null,
          isUnavailable: true,
        ),
  ];
}

String _unavailableMemberLabel(BuildContext context) {
  return context.l10n.customFieldMemberUnavailable;
}

Set<String> _parseMemberReferenceIds(CustomField field, String raw) {
  if (field.fieldTypeId != 'member') return const <String>{};
  final parsed = customFieldTypeRegistry.lookupById('member')?.valueParser(raw);
  if (parsed is MemberFieldValue) {
    final parsedIds = _stableNonEmptyIds(parsed.memberIds);
    if (parsedIds.isNotEmpty) return parsedIds;
  }

  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const <String>{};

  try {
    final decoded = jsonDecode(trimmed);
    final ids = _extractMemberReferenceIds(decoded);
    if (ids.isNotEmpty) return ids;
  } catch (_) {
    // Older or malformed peers should not leak raw JSON into settings.
  }

  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return const <String>{};
  }
  return _stableNonEmptyIds([trimmed]);
}

Set<String> _extractMemberReferenceIds(Object? decoded) {
  if (decoded is String) return _stableNonEmptyIds([decoded]);
  if (decoded is List) {
    return _stableNonEmptyIds(decoded.whereType<String>());
  }
  if (decoded is Map) {
    return _stableNonEmptyIds([
      if (decoded['memberId'] case final String id) id,
      if (decoded['id'] case final String id) id,
      if (decoded['memberIds'] case final List ids) ...ids.whereType<String>(),
      if (decoded['members'] case final List ids) ...ids.whereType<String>(),
      if (decoded['selectedMemberIds'] case final List ids)
        ...ids.whereType<String>(),
    ]);
  }
  return const <String>{};
}

Set<String> _stableNonEmptyIds(Iterable<String> ids) {
  return {
    for (final id in ids)
      if (id.trim().isNotEmpty) id.trim(),
  };
}

/// Resolves a raw choice JSON string into a comma-separated list of option
/// labels. Returns an empty string if nothing can be resolved.
String _formatChoiceValue(BuildContext context, CustomField field, String raw) {
  final parsed = choiceFieldDefinition.valueParser(raw);
  if (parsed is! ChoiceFieldValue) return '';
  final config = field.typeConfig;
  if (config is! ChoiceConfig) return '';

  final optionsById = {for (final o in config.options) o.id: o};
  final labels = parsed.optionIds
      .map((id) => optionsById[id]?.label)
      .whereType<String>()
      .where((l) => l.isNotEmpty)
      .toList();
  if (parsed.other != null && parsed.other!.isNotEmpty) {
    labels.add(context.l10n.customFieldChoiceOtherPrefix(parsed.other!));
  }
  return labels.join(', ');
}

String _formatDateValue(
  BuildContext context,
  String raw,
  DatePrecision? precision,
) {
  final locale = context.dateLocale;
  try {
    final dt = DateTime.parse(raw);
    return switch (precision ?? DatePrecision.full) {
      DatePrecision.full => DateFormat.yMMMd(locale).format(dt),
      DatePrecision.monthYear => DateFormat.yMMM(locale).format(dt),
      DatePrecision.monthDay => DateFormat.MMMd(locale).format(dt),
      DatePrecision.month => DateFormat.MMMM(locale).format(dt),
      DatePrecision.year => DateFormat.y(locale).format(dt),
      DatePrecision.timestamp =>
        '${DateFormat.yMMMd(locale).format(dt)} ${context.formatTime(dt)}',
    };
  } catch (_) {
    return raw;
  }
}

int _compareFieldOrder(CustomField a, CustomField b) {
  final byOrder = a.displayOrder.compareTo(b.displayOrder);
  if (byOrder != 0) return byOrder;
  final byCreatedAt = a.createdAt.compareTo(b.createdAt);
  if (byCreatedAt != 0) return byCreatedAt;
  return a.id.compareTo(b.id);
}

// ─── Group contents section ─────────────────────────────────────────────────

/// Within-group reorder via drag handles; cross-group moves still use the
/// long-press menu on the main list.
class _GroupContentsSection extends ConsumerStatefulWidget {
  const _GroupContentsSection({required this.group});

  final CustomField group;

  @override
  ConsumerState<_GroupContentsSection> createState() =>
      _GroupContentsSectionState();
}

class _GroupContentsSectionState extends ConsumerState<_GroupContentsSection> {
  final OptimisticListController<CustomField, String> _optimisticChildren =
      OptimisticListController<CustomField, String>(keyOf: (field) => field.id);

  @override
  void didUpdateWidget(covariant _GroupContentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.id != widget.group.id) {
      _optimisticChildren.clear();
    }
  }

  void _clearOptimisticChildrenAfterBuild(List<CustomField> current) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_optimisticChildren.isCurrent(current)) return;
      setState(_optimisticChildren.clear);
    });
  }

  void _persistReorder(List<CustomField> reordered) {
    unawaited(
      ref
          .read(customFieldNotifierProvider.notifier)
          .reorderFields(reordered)
          .catchError((Object error, StackTrace _) {
            if (!mounted || !_optimisticChildren.hasCurrentOrder(reordered)) {
              return;
            }
            setState(_optimisticChildren.clear);
            PrismToast.error(
              context,
              message: context.l10n.settingsCustomFieldsError(error.toString()),
            );
          }),
    );
  }

  void _onReorder(List<CustomField> children, int oldIndex, int newIndex) {
    final reordered = reorderedItems(children, oldIndex, newIndex);
    if (reordered == null) return;
    setState(() => _optimisticChildren.set(reordered));
    _persistReorder(reordered);
    Haptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fieldsAsync = ref.watch(customFieldsProvider);
    final memberTypeLabel = watchTerminology(context, ref).singular;

    return fieldsAsync.when(
      loading: () => const PrismLoadingState(),
      error: (e, _) => Center(
        child: Text(context.l10n.settingsCustomFieldsError(e.toString())),
      ),
      data: (allFields) {
        final providerChildren =
            allFields.where((f) => f.parentFieldId == widget.group.id).toList()
              ..sort(_compareFieldOrder);
        final optimisticChildren = _optimisticChildren.items;
        final children = _optimisticChildren.displayItems(providerChildren);
        if (_optimisticChildren.shouldClearFor(providerChildren) &&
            optimisticChildren != null) {
          _clearOptimisticChildrenAfterBuild(optimisticChildren);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  AppIcons.folderOutlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.customFieldGroupChildrenHeading,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                PrismInlineIconButton(
                  icon: AppIcons.add,
                  iconSize: 20,
                  color: theme.colorScheme.primary,
                  onPressed: () => _openAddChildSheet(context),
                  tooltip: context.l10n.settingsCustomFieldsAddTooltip,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.customFieldGroupChildrenCount(children.length),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (children.isEmpty)
              EmptyState(
                icon: Icon(AppIcons.folderOutlined),
                title: context.l10n.customFieldGroupChildrenEmptyTitle,
                subtitle: context.l10n.customFieldGroupChildrenEmptySubtitle,
              )
            else
              PrismSectionCard(
                padding: EdgeInsets.zero,
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: children.length,
                  onReorder: (oldIndex, newIndex) =>
                      _onReorder(children, oldIndex, newIndex),
                  proxyDecorator: (child, _, _) => Material(
                    elevation: 2,
                    color: theme.colorScheme.surface,
                    child: child,
                  ),
                  itemBuilder: (context, i) {
                    return _GroupChildRow(
                      key: ValueKey(children[i].id),
                      child: children[i],
                      index: i,
                      memberTypeLabel: memberTypeLabel,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  void _openAddChildSheet(BuildContext context) {
    PrismSheet.showFullScreen(
      context: context,
      builder: (ctx, scrollController) => CreateEditFieldSheet(
        scrollController: scrollController,
        parentFieldId: widget.group.id,
      ),
    );
  }
}

class _GroupChildRow extends StatelessWidget {
  const _GroupChildRow({
    super.key,
    required this.child,
    required this.index,
    required this.memberTypeLabel,
  });

  final CustomField child;
  final int index;
  final String memberTypeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final def = customFieldTypeRegistry.lookupById(child.fieldTypeId);
    final icon = def?.icon ?? AppIcons.textFields;
    final subtitle = _childSubtitle(context, child, def);

    return PrismListRow(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(child.name),
      subtitle: Text(
        subtitle,
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
      onTap: () => context.push(AppRoutePaths.settingsCustomField(child.id)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  String _childSubtitle(
    BuildContext context,
    CustomField field,
    CustomFieldTypeDefinition? def,
  ) {
    final l10n = context.l10n;
    final label = localizedFieldTypeLabel(
      l10n,
      field,
      memberTypeLabel: memberTypeLabel,
    );
    if (def != null &&
        field.fieldType == CustomFieldType.date &&
        field.datePrecision != null) {
      return '$label • ${field.datePrecision!.localizedLabel(l10n)}';
    }
    return label;
  }
}
