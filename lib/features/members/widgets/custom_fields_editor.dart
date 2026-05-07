import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/chat/widgets/chat_markdown_editing_controller.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/full_screen_markdown_editor_sheet.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_time_picker.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';

/// Inline editor for custom field values on the member edit sheet.
class CustomFieldsEditor extends ConsumerWidget {
  const CustomFieldsEditor({
    super.key,
    required this.memberId,
    this.controller,
  });

  final String memberId;
  final CustomFieldsEditorController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fieldsAsync = ref.watch(customFieldsProvider);

    return fieldsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (fields) {
        if (fields.isEmpty) return const SizedBox.shrink();

        final valuesAsync = ref.watch(
          memberCustomFieldValuesProvider(memberId),
        );
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
    final l10n = context.l10n;

    final valueMap = <String, CustomFieldValue>{
      for (final v in values) v.customFieldId: v,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(
              AppIcons.tuneOutlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
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
        const SizedBox(height: 12),
        for (final field in fields) ...[
          _FieldInput(
            field: field,
            memberId: memberId,
            existingValue: valueMap[field.id],
            controller: controller,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class CustomFieldsEditorController {
  final Set<_FieldInputState> _inputs = {};

  Future<void> savePendingValues() async {
    for (final input in List<_FieldInputState>.of(_inputs)) {
      await input.savePendingValue();
    }
  }

  void _register(_FieldInputState input) {
    _inputs.add(input);
  }

  void _unregister(_FieldInputState input) {
    _inputs.remove(input);
  }
}

class _FieldInput extends ConsumerStatefulWidget {
  const _FieldInput({
    required this.field,
    required this.memberId,
    this.existingValue,
    this.controller,
  });

  final CustomField field;
  final String memberId;
  final CustomFieldValue? existingValue;
  final CustomFieldsEditorController? controller;

  @override
  ConsumerState<_FieldInput> createState() => _FieldInputState();
}

class _FieldInputState extends ConsumerState<_FieldInput> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late final CustomFieldValueNotifier _valueNotifier;
  late String _lastSavedValue;

  @override
  void initState() {
    super.initState();
    _valueNotifier = ref.read(customFieldValueNotifierProvider.notifier);
    _focusNode = FocusNode();
    widget.controller?._register(this);
    final initialValue = widget.existingValue?.value ?? '';
    _lastSavedValue = initialValue;
    _textController = switch (widget.field.fieldType) {
      CustomFieldType.text => ChatMarkdownEditingController(text: initialValue),
      CustomFieldType.longText => MarkdownEditingController(text: initialValue),
      CustomFieldType.color ||
      CustomFieldType.date => TextEditingController(text: initialValue),
    };
  }

  @override
  void didUpdateWidget(covariant _FieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newVal = widget.existingValue?.value ?? '';
    if (oldWidget.existingValue?.value != newVal) {
      _lastSavedValue = newVal;
    }
    if (oldWidget.existingValue?.value != newVal &&
        !_focusNode.hasFocus &&
        _textController.text != newVal) {
      _textController.text = newVal;
    }
  }

  @override
  void dispose() {
    widget.controller?._unregister(this);
    unawaited(savePendingValue());
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> savePendingValue() async {
    switch (widget.field.fieldType) {
      case CustomFieldType.text:
      case CustomFieldType.longText:
      case CustomFieldType.color:
        await _saveValue(_textController.text.trim());
      case CustomFieldType.date:
        break;
    }
  }

  Future<void> _saveValue(String value) async {
    if (value == _lastSavedValue) return;

    if (value.isEmpty && widget.existingValue != null) {
      _lastSavedValue = '';
      await _valueNotifier.deleteValue(widget.existingValue!.id);
      return;
    }
    if (value.isEmpty) return;

    _lastSavedValue = value;
    await _valueNotifier.setValue(
      customFieldId: widget.field.id,
      memberId: widget.memberId,
      value: value,
      existingId: widget.existingValue?.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _textController;
    if (controller is ChatMarkdownEditingController) {
      controller.updateTheme(context);
    } else if (controller is MarkdownEditingController) {
      controller.updateTheme(context);
    }

    return switch (widget.field.fieldType) {
      CustomFieldType.text => _buildTextInput(context),
      CustomFieldType.longText => _buildLongTextInput(context),
      CustomFieldType.color => _buildColorInput(context),
      CustomFieldType.date => _buildDateInput(context),
    };
  }

  Widget _buildTextInput(BuildContext context) {
    final l10n = context.l10n;
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) unawaited(savePendingValue());
      },
      child: PrismTextField(
        focusNode: _focusNode,
        controller: _textController,
        labelText: widget.field.name,
        hintText: l10n.memberCustomFieldEnterHint(
          widget.field.name.toLowerCase(),
        ),
        onChanged: (_) {},
        onSubmitted: (value) => unawaited(_saveValue(value)),
      ),
    );
  }

  Widget _buildLongTextInput(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.field.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            PrismIconButton(
              icon: AppIcons.edit,
              tooltip: l10n.edit,
              semanticLabel: l10n.terminologyEditItem(widget.field.name),
              onPressed: () => _openLongTextEditor(context),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) unawaited(savePendingValue());
          },
          child: PrismTextField(
            focusNode: _focusNode,
            controller: _textController,
            hintText: l10n.memberCustomFieldEnterHint(
              widget.field.name.toLowerCase(),
            ),
            keyboardType: TextInputType.multiline,
            minLines: 5,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {},
          ),
        ),
      ],
    );
  }

  Future<void> _openLongTextEditor(BuildContext context) async {
    final result = await showFullScreenMarkdownEditor(
      context: context,
      title: widget.field.name,
      initialText: _textController.text,
      hintText: context.l10n.memberCustomFieldEnterHint(
        widget.field.name.toLowerCase(),
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _textController.text = result);
    await _saveValue(result);
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
        if (!hasFocus) unawaited(savePendingValue());
      },
      child: PrismTextField(
        focusNode: _focusNode,
        controller: _textController,
        labelText: widget.field.name,
        hintText: '#AF8EE9',
        onChanged: (val) => setState(() {}),
        onSubmitted: (value) => unawaited(_saveValue(value)),
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
    final l10n = context.l10n;
    final locale = context.dateLocale;
    final precision = widget.field.datePrecision ?? DatePrecision.full;
    final currentValue = _textController.text.trim();
    String displayText = '';

    if (currentValue.isNotEmpty) {
      try {
        final dt = DateTime.parse(currentValue);
        displayText = _formatForPrecision(dt, precision, locale);
      } catch (_) {
        displayText = currentValue;
      }
    }

    final dateField = Builder(
      builder: (anchorContext) => GestureDetector(
        onTap: () => _pickDate(context, anchorContext, precision),
        child: InputDecorator(
          decoration: InputDecoration(
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (currentValue.isNotEmpty)
                  PrismFieldIconButton(
                    icon: AppIcons.clear,
                    color: theme.colorScheme.onSurfaceVariant,
                    onPressed: () {
                      _textController.text = '';
                      if (widget.existingValue != null) {
                        unawaited(
                          ref
                              .read(customFieldValueNotifierProvider.notifier)
                              .deleteValue(widget.existingValue!.id),
                        );
                      }
                      setState(() {});
                    },
                    tooltip: l10n.memberClearDateTooltip,
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
            displayText.isNotEmpty
                ? displayText
                : l10n.memberCustomFieldSelectDate,
            style: displayText.isNotEmpty
                ? theme.textTheme.bodyLarge
                : theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.field.name,
          style: theme.textTheme.labelLarge!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Semantics(label: widget.field.name, button: true, child: dateField),
      ],
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    BuildContext anchorContext,
    DatePrecision precision,
  ) async {
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
        final picked = await showPrismDatePicker(
          context: context,
          anchorContext: anchorContext,
          initialDate: initial,
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
          initialDatePickerMode:
              precision == DatePrecision.year ||
                  precision == DatePrecision.monthYear
              ? DatePickerMode.year
              : DatePickerMode.day,
        );
        if (picked != null && mounted) {
          _textController.text = picked.toIso8601String();
          await _saveValue(_textController.text);
          setState(() {});
        }

      case DatePrecision.monthDay:
        final picked = await showPrismDatePicker(
          context: context,
          anchorContext: anchorContext,
          initialDate: initial,
          firstDate: DateTime(2000, 1, 1),
          lastDate: DateTime(2000, 12, 31),
        );
        if (picked != null && mounted) {
          _textController.text = picked.toIso8601String();
          await _saveValue(_textController.text);
          setState(() {});
        }

      case DatePrecision.month:
        final picked = await showPrismDatePicker(
          context: context,
          anchorContext: anchorContext,
          initialDate: initial,
          firstDate: DateTime(2000, 1, 1),
          lastDate: DateTime(2000, 12, 31),
          initialDatePickerMode: DatePickerMode.year,
        );
        if (picked != null && mounted) {
          _textController.text = picked.toIso8601String();
          await _saveValue(_textController.text);
          setState(() {});
        }

      case DatePrecision.timestamp:
        final pickedDate = await showPrismDatePicker(
          context: context,
          anchorContext: anchorContext,
          initialDate: initial,
          firstDate: DateTime(1900),
          lastDate: DateTime(2100),
        );
        if (pickedDate == null || !context.mounted) return;
        final pickedTime = await showPrismTimePicker(
          context: context,
          anchorContext: anchorContext,
          initialTime: TimeOfDay.fromDateTime(initial),
        );
        if (!mounted) return;
        final time = pickedTime ?? TimeOfDay.fromDateTime(initial);
        final combined = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          time.hour,
          time.minute,
        );
        _textController.text = combined.toIso8601String();
        await _saveValue(_textController.text);
        setState(() {});
    }
  }

  String _formatForPrecision(
    DateTime dt,
    DatePrecision precision,
    String locale,
  ) {
    return switch (precision) {
      DatePrecision.full => DateFormat.yMMMd(locale).format(dt),
      DatePrecision.monthYear => DateFormat.yMMM(locale).format(dt),
      DatePrecision.monthDay => DateFormat.MMMd(locale).format(dt),
      DatePrecision.month => DateFormat.MMMM(locale).format(dt),
      DatePrecision.year => DateFormat.y(locale).format(dt),
      DatePrecision.timestamp => DateFormat.yMMMd(locale).add_jm().format(dt),
    };
  }
}
