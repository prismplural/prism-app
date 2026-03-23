import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';

/// Displays custom field values on a member detail screen.
///
/// Follows the same _SectionCard pattern used in member_detail_screen.dart.
/// Returns [SizedBox.shrink] when no fields have values set.
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
    // Build a map of customFieldId → value for quick lookup.
    final valueMap = <String, CustomFieldValue>{
      for (final v in values) v.customFieldId: v,
    };

    // Only show fields that have a value set.
    final fieldsWithValues = fields.where((f) {
      final v = valueMap[f.id];
      return v != null && v.value.isNotEmpty;
    }).toList();

    if (fieldsWithValues.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_outlined, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Custom Fields',
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
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
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
          _formatDateValue(value.value, field.datePrecision),
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

  String _formatDateValue(String raw, DatePrecision? precision) {
    try {
      final dt = DateTime.parse(raw);
      return switch (precision ?? DatePrecision.full) {
        DatePrecision.full => DateFormat.yMMMd().format(dt),
        DatePrecision.monthYear => DateFormat.yMMM().format(dt),
        DatePrecision.monthDay => DateFormat.MMMd().format(dt),
        DatePrecision.month => DateFormat.MMMM().format(dt),
        DatePrecision.year => DateFormat.y().format(dt),
        DatePrecision.timestamp => DateFormat.yMMMd().add_jm().format(dt),
      };
    } catch (_) {
      return raw;
    }
  }
}
