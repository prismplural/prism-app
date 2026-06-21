import 'package:flutter/material.dart';

import 'package:prism_plurality/domain/custom_fields/field_template.dart';
import 'package:prism_plurality/domain/custom_fields/registry.dart';
import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_type_config.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/utils/custom_field_type_labels.dart';
import 'package:prism_plurality/shared/widgets/custom_field_header_icon.dart';

/// Presentation-only summary of one template field. Shared by the share
/// "what's included" list and the import preview (the trust surface) so both
/// describe a template identically.
class FieldTemplateSummaryItem {
  const FieldTemplateSummaryItem({
    required this.name,
    required this.typeLabel,
    required this.icon,
    required this.field,
    required this.isGroup,
    required this.isChild,
    required this.isUnknownType,
    required this.swatches,
    this.scaleEmoji,
    this.scaleSteps,
  });

  final String name;
  final String typeLabel;

  /// Generic type glyph, shown when the field has no custom header icon.
  final IconData icon;

  /// The inflated domain field (display-only) — lets the row render the
  /// author's chosen header icon, matching the main field list.
  final CustomField field;
  final bool isGroup;
  final bool isChild;

  /// A forward-compat type this build doesn't recognise (imports as-is).
  final bool isUnknownType;

  /// Resolved colours of a choice field's options (empty for other types).
  final List<Color> swatches;

  /// Scale field emoji + step count (null for other types).
  final String? scaleEmoji;
  final int? scaleSteps;
}

/// Derives display items from [template] by inflating it to domain fields
/// (fresh ids — display only) and reading each field's real config, so the
/// swatches and emoji shown match exactly what an import would create.
///
/// [toDomainFields] mints fresh ids on every call, so widgets that rebuild
/// should inflate once and call [summarizeDomainFields] instead.
List<FieldTemplateSummaryItem> summarizeFieldTemplate(
  AppLocalizations l10n,
  FieldTemplate template, {
  String? memberTypeLabel,
  String groupNameFallback = '',
}) => summarizeDomainFields(
  l10n,
  template.toDomainFields(),
  memberTypeLabel: memberTypeLabel,
  groupNameFallback: groupNameFallback,
);

/// Maps already-inflated domain [fields] to display items. Pure and cheap —
/// safe to call in `build()` once the fields are inflated once up front.
List<FieldTemplateSummaryItem> summarizeDomainFields(
  AppLocalizations l10n,
  List<CustomField> fields, {
  String? memberTypeLabel,
  String groupNameFallback = '',
}) {
  return [
    for (final field in fields)
      _itemFor(
        l10n,
        field,
        memberTypeLabel: memberTypeLabel,
        groupNameFallback: groupNameFallback,
      ),
  ];
}

FieldTemplateSummaryItem _itemFor(
  AppLocalizations l10n,
  CustomField field, {
  String? memberTypeLabel,
  required String groupNameFallback,
}) {
  final def = customFieldTypeRegistry.lookupById(field.fieldTypeId);
  final isGroup = field.fieldTypeId == kGroupFieldTypeId;
  final isUnknown = def == null || field.unknownTypeConfigRaw != null;
  final config = field.typeConfig;

  final swatches = <Color>[];
  if (config is ChoiceConfig) {
    for (final option in config.options) {
      final hex = option.colorHex;
      if (hex != null && hex.isNotEmpty) swatches.add(AppColors.fromHex(hex));
    }
  }

  String? scaleEmoji;
  int? scaleSteps;
  if (config is ScaleConfig) {
    scaleEmoji = config.emoji;
    scaleSteps = config.steps;
  }

  final name = isGroup && field.name.trim().isEmpty
      ? groupNameFallback
      : field.name;
  // Unknown types have no localized label, so surface the raw id rather than
  // mislabel them.
  final typeLabel = isUnknown
      ? (field.fieldTypeId ?? '')
      : localizedFieldTypeLabel(l10n, field, memberTypeLabel: memberTypeLabel);
  final icon = isGroup
      ? AppIcons.folderOutlined
      : (def?.icon ?? AppIcons.textFields);

  return FieldTemplateSummaryItem(
    name: name,
    typeLabel: typeLabel,
    icon: icon,
    field: field,
    isGroup: isGroup,
    isChild: field.parentFieldId != null,
    isUnknownType: isUnknown,
    swatches: swatches,
    scaleEmoji: scaleEmoji,
    scaleSteps: scaleSteps,
  );
}

/// One row describing a template field: type icon, name, type label, choice
/// swatches, scale emoji, and an inline "newer version" badge for unknown types.
class FieldTemplateSummaryRow extends StatelessWidget {
  const FieldTemplateSummaryRow({super.key, required this.item});

  final FieldTemplateSummaryItem item;

  static const _maxSwatches = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final typeLine = item.scaleEmoji != null
        ? '${item.typeLabel} • ${item.scaleEmoji} ×${item.scaleSteps}'
        : item.typeLabel;

    return Semantics(
      label: context.l10n.fieldTemplatePreviewRowSemantic(item.name, typeLine),
      child: Padding(
        padding: EdgeInsets.fromLTRB(item.isChild ? 20 : 0, 8, 0, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show the author's header icon when set, else the type glyph —
            // mirrors the main field list so the preview looks like the real fields.
            hasRenderableCustomFieldHeaderIcon(item.field)
                ? CustomFieldHeaderIconView(
                    field: item.field,
                    size: 20,
                    color: theme.colorScheme.primary,
                  )
                : Icon(item.icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      if (item.isUnknownType) ...[
                        const SizedBox(width: 8),
                        const _NewerVersionBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    typeLine,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  if (item.swatches.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _SwatchRow(swatches: item.swatches, max: _maxSwatches),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow({required this.swatches, required this.max});

  final List<Color> swatches;
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = swatches.take(max).toList();
    final overflow = swatches.length - shown.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final color in shown)
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
          ),
        if (overflow > 0)
          Text(
            '+$overflow',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _NewerVersionBadge extends StatelessWidget {
  const _NewerVersionBadge();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        context.l10n.fieldTemplatePreviewUnknownBadge,
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.warning,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
