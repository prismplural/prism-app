import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/widgets/prism_section_card.dart';

/// Displays custom field values on a member detail screen.
class CustomFieldsDisplay extends ConsumerWidget {
  const CustomFieldsDisplay({super.key, required this.memberId});

  final String memberId;

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
        data: (values) => _buildContent(context, fields, values),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<CustomField> fields,
    List<CustomFieldValue> values,
  ) {
    final valueMap = <String, CustomFieldValue>{
      for (final v in values) v.customFieldId: v,
    };

    final fieldsWithValues = fields.where((f) {
      final v = valueMap[f.id];
      return v != null && v.value.isNotEmpty;
    }).toList();

    if (fieldsWithValues.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.tuneOutlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                l10n.memberSectionCustomFields,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: PrismSectionCard(
              child: Column(
                children: [
                  for (var i = 0; i < fieldsWithValues.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _FieldValueRow(
                      field: fieldsWithValues[i],
                      value: valueMap[fieldsWithValues[i].id]!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldValueRow extends StatelessWidget {
  const _FieldValueRow({required this.field, required this.value});

  final CustomField field;
  final CustomFieldValue value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              field.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: _buildValueDisplay(context),
          ),
        ],
      ),
    );
  }

  Widget _buildValueDisplay(BuildContext context) {
    final theme = Theme.of(context);

    return switch (field.fieldType) {
      CustomFieldType.text => Text(
          value.value,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.end,
        ),
      CustomFieldType.color => _buildColorDisplay(context),
      CustomFieldType.date => Text(
          _formatDateValue(context, value.value, field.datePrecision),
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.end,
        ),
    };
  }

  Widget _buildColorDisplay(BuildContext context) {
    final theme = Theme.of(context);
    final hex = value.value;
    Color? color;
    try {
      color = AppColors.fromHex(hex);
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
        Text(
          hex,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  String _formatDateValue(BuildContext context, String raw, DatePrecision? precision) {
    final locale = context.dateLocale;
    try {
      final dt = DateTime.parse(raw);
      return switch (precision ?? DatePrecision.full) {
        DatePrecision.full => DateFormat.yMMMd(locale).format(dt),
        DatePrecision.monthYear => DateFormat.yMMM(locale).format(dt),
        DatePrecision.monthDay => DateFormat.MMMd(locale).format(dt),
        DatePrecision.month => DateFormat.MMMM(locale).format(dt),
        DatePrecision.year => DateFormat.y(locale).format(dt),
        DatePrecision.timestamp => DateFormat.yMMMd(locale).add_jm().format(dt),
      };
    } catch (_) {
      return raw;
    }
  }
}
