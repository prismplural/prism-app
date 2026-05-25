import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/core/router/app_routes.dart';
import 'package:prism_plurality/domain/custom_fields/definitions/choice_field_definition.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/domain/models/typed_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/providers/members_providers.dart';
import 'package:prism_plurality/features/settings/providers/terminology_provider.dart';
import 'package:prism_plurality/features/settings/widgets/create_edit_field_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/haptics.dart';
import 'package:prism_plurality/shared/widgets/app_shell.dart';
import 'package:prism_plurality/shared/widgets/empty_state.dart';
import 'package:prism_plurality/shared/widgets/member_avatar.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
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
enum _MoveAction {
  moveIntoGroup,
  moveOutOfGroup,
  moveToAnotherGroup,
}

class _CustomFieldDetailBodyState extends ConsumerState<_CustomFieldDetailBody> {
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
    final allFieldsAsync = ref.watch(customFieldsProvider);
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
        moveItems.add(PrismMenuItem(
          value: _MoveAction.moveIntoGroup,
          label: context.l10n.customFieldMenuMoveIntoGroup,
          icon: AppIcons.folderOutlined,
        ));
      } else if (_allGroups(allFields).isNotEmpty) {
        moveItems.add(PrismMenuItem(
          value: _MoveAction.moveIntoGroup,
          label: context.l10n.customFieldNoEligibleGroups,
          icon: AppIcons.folderOutlined,
          enabled: false,
        ));
      }
    }
    if (isNested) {
      moveItems.add(PrismMenuItem(
        value: _MoveAction.moveOutOfGroup,
        label: context.l10n.customFieldMenuMoveOutOfGroup,
        icon: AppIcons.arrowUpward,
      ));
      if (otherGroups.isNotEmpty) {
        moveItems.add(PrismMenuItem(
          value: _MoveAction.moveToAnotherGroup,
          label: context.l10n.customFieldMenuMoveToAnotherGroup,
          icon: AppIcons.arrowForward,
        ));
      }
    }

    return PrismPageScaffold(
      topBar: PrismTopBar(
        title: '',
        showBackButton: true,
        actions: [
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
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 16, 24, NavBarInset.of(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _iconForField(field),
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        field.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
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
                      value: field.datePrecision!.localizedLabel(context.l10n),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            _FilledInSection(field: field),
          ],
        ),
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
    final selected = await showDialog<CustomField>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final group in groups)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(group),
              child: Row(
                children: [
                  Icon(AppIcons.folderOutlined, size: 20),
                  const SizedBox(width: 12),
                  Text(group.name),
                ],
              ),
            ),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                context.l10n.customFieldNoEligibleGroups,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
    if (selected != null) onSelected(selected);
  }

  Future<void> _moveIntoGroup(BuildContext context, CustomField targetGroup) async {
    await ref.read(customFieldNotifierProvider.notifier).updateField(
          field.copyWith(parentFieldId: targetGroup.id),
        );
    if (context.mounted) {
      PrismToast.show(
        context,
        message: '${field.name} moved into ${targetGroup.name}',
      );
    }
  }

  Future<void> _moveOutOfGroup(BuildContext context) async {
    await ref.read(customFieldNotifierProvider.notifier).updateField(
          field.copyWith(parentFieldId: null),
        );
    if (context.mounted) {
      PrismToast.show(
        context,
        message: '${field.name} moved to top level',
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final navigator = Navigator.of(context);
    final router = GoRouter.maybeOf(context);
    final deletedToast = context.l10n.settingsCustomFieldsDeletedToast(
      field.name,
    );

    bool? deleteChildren; // null = cancel, false = promote, true = delete children

    if (field.fieldTypeId == 'group') {
      deleteChildren = await showDialog<bool?>(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            title: Text(context.l10n.customFieldGroupDeleteTitle(field.name)),
            content: Text(context.l10n.customFieldGroupDeleteMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(context.l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: Text(context.l10n.customFieldGroupDeleteChildren),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(context.l10n.customFieldGroupPromoteChildren),
              ),
            ],
          );
        },
      );
      if (deleteChildren == null) return; // user cancelled
    } else {
      final confirmed = await PrismDialog.confirm(
        context: context,
        title: context.l10n.settingsCustomFieldsDeleteTitle,
        message: context.l10n.settingsCustomFieldsDeleteConfirm(field.name),
        confirmLabel: context.l10n.delete,
        destructive: true,
      );
      if (!confirmed) return;
      deleteChildren = false; // non-group, parameter has no effect
    }

    Haptics.heavy();
    await ref.read(customFieldNotifierProvider.notifier).deleteField(
          field.id,
          deleteChildren: deleteChildren,
        );
    if (context.mounted) {
      PrismToast.show(context, message: deletedToast);
    }
    if (router != null) {
      router.go(AppRoutePaths.settingsCustomFields);
    } else if (navigator.canPop()) {
      navigator.pop();
    }
  }

  /// Registry-driven icon. Falls back to enum-based lookup for legacy types
  /// if the registry entry has no entry (shouldn't happen in practice).
  IconData _iconForField(CustomField field) {
    final def = customFieldTypeRegistry.lookupById(field.fieldTypeId);
    if (def != null) return def.icon;
    // Legacy fallback for fields with no fieldTypeId (pre-registry rows).
    return switch (field.fieldType) {
      CustomFieldType.text => AppIcons.textFields,
      CustomFieldType.longText => AppIcons.notes,
      CustomFieldType.color => AppIcons.palette,
      CustomFieldType.date => AppIcons.calendarToday,
      CustomFieldType.choice => AppIcons.checkBoxOutlined,
    };
  }

  /// Registry-driven type label. The [CustomFieldTypeDefinition.labelL10nKey]
  /// is a string key that maps directly to the AppLocalizations method name.
  /// This bridge resolves known keys; unknown future types fall through to the
  /// legacy enum label.
  ///
  /// TODO: once AppLocalizations exposes a `resolve(key)` helper, replace
  /// this switch with a single call.
  String _labelForField(BuildContext context, CustomField field) {
    final l10n = context.l10n;
    final def = customFieldTypeRegistry.lookupById(field.fieldTypeId);
    if (def != null) {
      return switch (def.labelL10nKey) {
        'customFieldTypeShortText' => l10n.customFieldTypeShortText,
        'customFieldTypeLongText' => l10n.customFieldTypeLongText,
        'customFieldTypeColor' => l10n.customFieldTypeColor,
        'customFieldTypeDate' => l10n.customFieldTypeDate,
        'customFieldTypeChoice' => l10n.customFieldTypeChoice,
        'customFieldTypeGroup' => l10n.customFieldTypeGroup,
        _ => def.labelL10nKey, // unknown future type — show key as fallback
      };
    }
    // Legacy fallback for fields with no fieldTypeId.
    return field.fieldType.localizedLabel(l10n);
  }
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
    final membersAsync = ref.watch(userVisibleAllMembersProvider);

    return valuesAsync.when(
      loading: () => const PrismLoadingState(),
      error: (e, _) => Center(
        child: Text(context.l10n.settingsCustomFieldsError(e.toString())),
      ),
      data: (values) => membersAsync.when(
        loading: () => const PrismLoadingState(),
        error: (e, _) => Center(
          child: Text(context.l10n.settingsCustomFieldsError(e.toString())),
        ),
        data: (members) =>
            _FilledInContent(field: field, values: values, members: members),
      ),
    );
  }
}

class _FilledInContent extends ConsumerWidget {
  const _FilledInContent({
    required this.field,
    required this.values,
    required this.members,
  });

  final CustomField field;
  final List<CustomFieldValue> values;
  final List<Member> members;

  static const _longShortTextValueLength = 80;
  static const _longShortTextValueCount = 2;
  static const _longShortTextValueRatio = 0.5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final terms = watchTerminology(context, ref);
    final memberById = {for (final member in members) member.id: member};
    final entries = [
      for (final value in values)
        if (value.value.trim().isNotEmpty && memberById[value.memberId] != null)
          _FilledValueEntry(member: memberById[value.memberId]!, value: value),
    ];
    final showLengthHint = _shouldShowLongTextHint(entries);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          )
        else
          PrismSectionCard(
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _FilledValueRow(field: field, entry: entries[i]),
                ],
              ],
            ),
          ),
      ],
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
  const _FilledValueRow({required this.field, required this.entry});

  final CustomField field;
  final _FilledValueEntry entry;

  @override
  Widget build(BuildContext context) {
    final member = entry.member;
    final memberName = _memberDisplayName(member);
    final formattedValue = _formatValueForField(
      context,
      field,
      entry.value.value,
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
          memberName: memberName,
          emoji: member.emoji,
          customColorEnabled: member.customColorHex != null,
          customColorHex: member.customColorHex,
          size: 36,
        ),
        title: Text(memberName),
        subtitle: _ValuePreview(field: field, rawValue: entry.value.value),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  static String _memberDisplayName(Member member) {
    final displayName = member.displayName?.trim();
    return displayName == null || displayName.isEmpty
        ? member.name
        : displayName;
  }
}

class _ValuePreview extends StatelessWidget {
  const _ValuePreview({required this.field, required this.rawValue});

  static const _previewCharacterLimit = 220;
  static const _previewLineLimit = 4;

  final CustomField field;
  final String rawValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedValue = _formatValueForField(context, field, rawValue);

    if (field.fieldType == CustomFieldType.color) {
      return _ColorValue(value: rawValue);
    }

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
  String raw,
) {
  return switch (field.fieldType) {
    CustomFieldType.date => _formatDateValue(context, raw, field.datePrecision),
    // Fix 1: resolve choice JSON into human-readable labels instead of leaking raw JSON.
    CustomFieldType.choice => _formatChoiceValue(context, field, raw),
    CustomFieldType.text ||
    CustomFieldType.longText ||
    CustomFieldType.color => raw,
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
