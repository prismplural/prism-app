import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';

/// Inline editor for custom field values on the member edit sheet.
///
/// For each defined custom field, shows an appropriate input widget based on
/// the field type. Saves values via [CustomFieldValueNotifier.setValue] on
/// change.
class CustomFieldsEditor extends ConsumerWidget {
  const CustomFieldsEditor({super.key, required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync = ref.watch(customFieldsProvider);
    final valuesAsync = ref.watch(memberCustomFieldValuesProvider(memberId));

    return fieldsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (fields) {
        if (fields.isEmpty) return const SizedBox.shrink();

        return valuesAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (values) => _buildEditor(context, ref, fields, values),
        );
      },
    );
  }

  Widget _buildEditor(
    BuildContext context,
    WidgetRef ref,
    List<CustomField> fields,
    List<CustomFieldValue> values,
  ) {
    final theme = Theme.of(context);

    // Build a map of customFieldId -> value for quick lookup.
    final valueMap = <String, CustomFieldValue>{
      for (final v in values) v.customFieldId: v,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(AppIcons.tuneOutlined, size: 18, color: theme.colorScheme.primary),
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
        const SizedBox(height: 12),
        for (final field in fields) ...[
          _FieldInput(
            field: field,
            memberId: memberId,
            existingValue: valueMap[field.id],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _FieldInput extends ConsumerStatefulWidget {
  const _FieldInput({
    required this.field,
    required this.memberId,
    this.existingValue,
  });

  final CustomField field;
  final String memberId;
  final CustomFieldValue? existingValue;

  @override
  ConsumerState<_FieldInput> createState() => _FieldInputState();
}

class _FieldInputState extends ConsumerState<_FieldInput> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: widget.existingValue?.value ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _FieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update controller if external value changed (e.g. from sync).
    final newVal = widget.existingValue?.value ?? '';
    if (oldWidget.existingValue?.value != newVal &&
        _textController.text != newVal) {
      _textController.text = newVal;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _saveValue(String value) {
    if (value.isEmpty && widget.existingValue != null) {
      ref
          .read(customFieldValueNotifierProvider.notifier)
          .deleteValue(widget.existingValue!.id);
      return;
    }
    if (value.isEmpty) return;

    ref.read(customFieldValueNotifierProvider.notifier).setValue(
          customFieldId: widget.field.id,
          memberId: widget.memberId,
          value: value,
          existingId: widget.existingValue?.id,
        );
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.field.fieldType) {
      CustomFieldType.text => _buildTextInput(),
      CustomFieldType.color => _buildColorInput(context),
      CustomFieldType.date => _buildDateInput(context),
    };
  }

  Widget _buildTextInput() {
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) _saveValue(_textController.text.trim());
      },
      child: PrismTextField(
        controller: _textController,
        labelText: widget.field.name,
        hintText: 'Enter ${widget.field.name.toLowerCase()}',
        onChanged: (_) {},
        onSubmitted: _saveValue,
      ),
    );
  }

  Widget _buildColorInput(BuildContext context) {
    final theme = Theme.of(context);
    Color? previewColor;
    try {
      final hex = _textController.text.trim();
      if (hex.isNotEmpty) previewColor = AppColors.fromHex(hex);
    } catch (_) {
      // Invalid hex — no preview.
    }

    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) _saveValue(_textController.text.trim());
      },
      child: PrismTextField(
      controller: _textController,
      labelText: widget.field.name,
      hintText: '#AF8EE9',
      onChanged: (val) => setState(() {}),
      onSubmitted: _saveValue,
      suffix: previewColor != null
          ? Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: previewColor,
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
              ),
            )
          : null,
    ),
    );
  }

  Widget _buildDateInput(BuildContext context) {
    final theme = Theme.of(context);
    final precision = widget.field.datePrecision ?? DatePrecision.full;
    final currentValue = _textController.text.trim();
    String displayText = '';

    if (currentValue.isNotEmpty) {
      try {
        final dt = DateTime.parse(currentValue);
        displayText = _formatForPrecision(dt, precision);
      } catch (_) {
        displayText = currentValue;
      }
    }

    return GestureDetector(
      onTap: () => _pickDate(context, precision),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.field.name,
          border: const OutlineInputBorder(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (currentValue.isNotEmpty)
                IconButton(
                  icon: Icon(
                    AppIcons.clear,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    _textController.text = '';
                    if (widget.existingValue != null) {
                      ref
                          .read(customFieldValueNotifierProvider.notifier)
                          .deleteValue(widget.existingValue!.id);
                    }
                    setState(() {});
                  },
                ),
              Icon(
                AppIcons.calendarToday,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
        child: Text(
          displayText.isNotEmpty ? displayText : 'Select date',
          style: displayText.isNotEmpty
              ? theme.textTheme.bodyLarge
              : theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context, DatePrecision precision) async {
    DateTime? initial;
    try {
      final cur = _textController.text.trim();
      if (cur.isNotEmpty) initial = DateTime.parse(cur);
    } catch (_) {
      // Ignore parse errors.
    }
    initial ??= DateTime.now();

    switch (precision) {
      case DatePrecision.full:
      case DatePrecision.monthYear:
      case DatePrecision.year:
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
          initialDatePickerMode: precision == DatePrecision.year ||
                  precision == DatePrecision.monthYear
              ? DatePickerMode.year
              : DatePickerMode.day,
        );
        if (picked != null && mounted) {
          _textController.text = picked.toIso8601String();
          _saveValue(_textController.text);
          setState(() {});
        }

      case DatePrecision.monthDay:
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2000, 1, 1),
          lastDate: DateTime(2000, 12, 31),
        );
        if (picked != null && mounted) {
          // Store with year 2000 as a placeholder.
          _textController.text = picked.toIso8601String();
          _saveValue(_textController.text);
          setState(() {});
        }

      case DatePrecision.month:
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(2000, 1, 1),
          lastDate: DateTime(2000, 12, 31),
          initialDatePickerMode: DatePickerMode.year,
        );
        if (picked != null && mounted) {
          _textController.text = picked.toIso8601String();
          _saveValue(_textController.text);
          setState(() {});
        }

      case DatePrecision.timestamp:
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
        );
        if (pickedDate != null && mounted) {
          final pickedTime = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(initial),
          );
          if (mounted) {
            final time = pickedTime ?? TimeOfDay.fromDateTime(initial);
            final combined = DateTime(
              pickedDate.year,
              pickedDate.month,
              pickedDate.day,
              time.hour,
              time.minute,
            );
            _textController.text = combined.toIso8601String();
            _saveValue(_textController.text);
            setState(() {});
          }
        }
    }
  }

  String _formatForPrecision(DateTime dt, DatePrecision precision) {
    return switch (precision) {
      DatePrecision.full => DateFormat.yMMMd().format(dt),
      DatePrecision.monthYear => DateFormat.yMMM().format(dt),
      DatePrecision.monthDay => DateFormat.MMMd().format(dt),
      DatePrecision.month => DateFormat.MMMM().format(dt),
      DatePrecision.year => DateFormat.y().format(dt),
      DatePrecision.timestamp => DateFormat.yMMMd().add_jm().format(dt),
    };
  }
}
