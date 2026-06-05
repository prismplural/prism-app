import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:prism_plurality/domain/models/custom_field.dart';
import 'package:prism_plurality/domain/models/custom_field_value.dart';
import 'package:prism_plurality/features/chat/widgets/chat_markdown_editing_controller.dart';
import 'package:prism_plurality/features/members/providers/custom_fields_providers.dart';
import 'package:prism_plurality/features/members/widgets/custom_field_editor_scope.dart';
import 'package:prism_plurality/features/members/widgets/full_screen_markdown_editor_sheet.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/theme/app_colors.dart';
import 'package:prism_plurality/shared/theme/app_icons.dart';
import 'package:prism_plurality/shared/widgets/markdown_editing_controller.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_color_picker_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_date_picker.dart';
import 'package:prism_plurality/shared/widgets/prism_field_icon_button.dart';
import 'package:prism_plurality/shared/widgets/prism_text_field.dart';
import 'package:prism_plurality/shared/widgets/prism_time_picker.dart';

/// Per-field editor for the four legacy custom-field types (text, longText,
/// color, date). Edits stage into the local [TextEditingController]; the host
/// drives persistence via [CustomFieldsEditorController.commit].
class FieldInputWidget extends ConsumerStatefulWidget {
  const FieldInputWidget({
    super.key,
    required this.field,
    required this.memberId,
    this.existingValue,
  });

  final CustomField field;
  final String memberId;
  final CustomFieldValue? existingValue;

  @override
  ConsumerState<FieldInputWidget> createState() => FieldInputWidgetState();
}

class FieldInputWidgetState extends ConsumerState<FieldInputWidget>
    with AutomaticKeepAliveClientMixin<FieldInputWidget>
    implements PendingFieldEditState {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late String _initialValue;
  CustomFieldsEditorController? _controller;
  bool _keepAlive = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _initialValue = widget.existingValue?.value ?? '';
    _textController = switch (widget.field.fieldType) {
      CustomFieldType.text => ChatMarkdownEditingController(
        text: _initialValue,
      ),
      CustomFieldType.longText => MarkdownEditingController(
        text: _initialValue,
      ),
      CustomFieldType.color ||
      CustomFieldType.date ||
      CustomFieldType.choice => TextEditingController(text: _initialValue),
    };
    _textController.addListener(_handleTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = CustomFieldEditorScope.maybeOf(context);
    if (identical(next, _controller)) return;
    _controller?.unregister(this);
    _controller = next;
    _controller?.register(this);
    _syncDirtyState();
  }

  @override
  void didUpdateWidget(covariant FieldInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newVal = widget.existingValue?.value ?? '';
    final oldVal = oldWidget.existingValue?.value ?? '';
    if (newVal == oldVal) return;
    // External update (sync stream). LWW for 0.10.0: focused user keeps
    // their in-progress text and wins on save; unfocused user's staged
    // edit is silently overwritten. Pinned by field_input_widget_test.dart.
    _initialValue = newVal;
    if (!_focusNode.hasFocus && _textController.text != newVal) {
      _textController.text = newVal;
    }
    _syncDirtyState();
  }

  @override
  void dispose() {
    _textController.removeListener(_handleTextChanged);
    _controller?.unregister(this);
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  bool get _isDirty => _textController.text.trim() != _initialValue.trim();

  @override
  bool get wantKeepAlive => _keepAlive;

  void _syncDirtyState() {
    final dirty = _isDirty;
    _controller?.markDirty(this, dirty);
    if (_keepAlive == dirty) return;
    _keepAlive = dirty;
    updateKeepAlive();
  }

  void _handleTextChanged() {
    _syncDirtyState();
  }

  @override
  String get fieldId => widget.field.id;

  @override
  String get fieldDisplayName => widget.field.name;

  @override
  Future<void> commitPendingValue() async {
    final value = _textController.text.trim();
    if (value == _initialValue.trim()) return;

    final notifier = ref.read(customFieldValueNotifierProvider.notifier);
    Object? failure;
    if (value.isEmpty) {
      final existingId = widget.existingValue?.id;
      if (existingId != null) {
        failure = await notifier.deleteValue(existingId);
      }
    } else {
      failure = await notifier.setValue(
        customFieldId: widget.field.id,
        memberId: widget.memberId,
        value: value,
        existingId: widget.existingValue?.id,
      );
    }
    // On failure: leave _initialValue alone and stay dirty so the bulk-commit
    // collects the error AND a re-touch re-stages and re-saves cleanly.
    if (failure != null) throw failure;
    _initialValue = value;
    _syncDirtyState();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final controller = _textController;
    if (controller is ChatMarkdownEditingController) {
      controller.updateTheme(context);
    } else if (controller is MarkdownEditingController) {
      controller.updateTheme(context);
    }

    // NOTE: CustomFieldType.choice is handled entirely by the renderer registry
    // (buildChoiceEditor in choice_field_widgets.dart). FieldInputWidget is
    // only reached for the 4 legacy types; dispatch in custom_fields_editor.dart
    // routes choice through the registry before it can reach this switch.
    return switch (widget.field.fieldType) {
      CustomFieldType.text => _buildTextInput(context),
      CustomFieldType.longText => _buildLongTextInput(context),
      CustomFieldType.color => _buildColorInput(context),
      CustomFieldType.date => _buildDateInput(context),
      CustomFieldType.choice => const SizedBox.shrink(),
    };
  }

  Widget _buildTextInput(BuildContext context) {
    final l10n = context.l10n;
    return PrismTextField(
      focusNode: _focusNode,
      controller: _textController,
      labelText: widget.field.name,
      hintText: l10n.memberCustomFieldEnterHint(
        widget.field.name.toLowerCase(),
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
        PrismTextField(
          focusNode: _focusNode,
          controller: _textController,
          hintText: l10n.memberCustomFieldEnterHint(
            widget.field.name.toLowerCase(),
          ),
          keyboardType: TextInputType.multiline,
          minLines: 5,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }

  Future<void> _openLongTextEditor(BuildContext context) async {
    final openInHost = CustomFieldEditorScope.maybeLongTextEditorOf(context);
    if (openInHost != null) {
      openInHost(widget.field, _textController, _focusNode);
      return;
    }

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

    return PrismTextField(
      focusNode: _focusNode,
      controller: _textController,
      labelText: widget.field.name,
      hintText: '#AF8EE9',
      onChanged: (val) => setState(() {}),
      suffix: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => _pickColor(context, previewColor),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: previewColor ?? Colors.transparent,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(
                  alpha: previewColor != null ? 0.3 : 0.7,
                ),
              ),
            ),
            child: previewColor == null
                ? Icon(
                    AppIcons.add,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> _pickColor(BuildContext context, Color? current) async {
    final initial = current ?? Theme.of(context).colorScheme.primary;
    final hex = await showPrismColorPickerDialog(
      context: context,
      initialColor: initial,
    );
    if (hex == null || !mounted) return;
    _textController.text = hex;
    setState(() {});
  }

  Widget _buildDateInput(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final precision = widget.field.datePrecision ?? DatePrecision.full;
    final currentValue = _textController.text.trim();
    String displayText = '';

    if (currentValue.isNotEmpty) {
      try {
        final dt = DateTime.parse(currentValue);
        displayText = _formatForPrecision(context, dt, precision);
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
      case DatePrecision.year:
        final picked = await showPrismDatePicker(
          context: context,
          anchorContext: anchorContext,
          initialDate: initial,
          firstDate: DateTime(1),
          lastDate: DateTime(9999, 12, 31),
          initialDatePickerMode: precision == DatePrecision.year
              ? DatePickerMode.year
              : DatePickerMode.day,
        );
        if (picked != null && mounted) {
          _textController.text = picked.toIso8601String();
          setState(() {});
        }

      case DatePrecision.monthYear:
        final picked = await showPrismMonthYearPicker(
          context: context,
          anchorContext: anchorContext,
          initialDate: initial,
          firstDate: DateTime(1),
          lastDate: DateTime(9999, 12, 31),
        );
        if (picked != null && mounted) {
          _textController.text = picked.toIso8601String();
          setState(() {});
        }

      case DatePrecision.monthDay:
        initial = _withYear(initial, 2000);
        final picked = await showPrismDatePicker(
          context: context,
          anchorContext: anchorContext,
          initialDate: initial,
          firstDate: DateTime(2000, 1, 1),
          lastDate: DateTime(2000, 12, 31),
        );
        if (picked != null && mounted) {
          _textController.text = picked.toIso8601String();
          setState(() {});
        }

      case DatePrecision.month:
        initial = _withYear(initial, 2000);
        final picked = await showPrismMonthYearPicker(
          context: context,
          anchorContext: anchorContext,
          initialDate: initial,
          firstDate: DateTime(2000, 1, 1),
          lastDate: DateTime(2000, 12, 31),
          includeYear: false,
        );
        if (picked != null && mounted) {
          _textController.text = picked.toIso8601String();
          setState(() {});
        }

      case DatePrecision.timestamp:
        final pickedDate = await showPrismDatePicker(
          context: context,
          anchorContext: anchorContext,
          initialDate: initial,
          firstDate: DateTime(1),
          lastDate: DateTime(9999, 12, 31),
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
        setState(() {});
    }
  }

  DateTime _withYear(DateTime date, int year) {
    final day = date.day.clamp(1, DateUtils.getDaysInMonth(year, date.month));
    return DateTime(year, date.month, day, date.hour, date.minute);
  }

  String _formatForPrecision(
    BuildContext context,
    DateTime dt,
    DatePrecision precision,
  ) {
    final locale = context.dateLocale;
    return switch (precision) {
      DatePrecision.full => DateFormat.yMMMd(locale).format(dt),
      DatePrecision.monthYear => DateFormat.yMMM(locale).format(dt),
      DatePrecision.monthDay => DateFormat.MMMd(locale).format(dt),
      DatePrecision.month => DateFormat.MMMM(locale).format(dt),
      DatePrecision.year => DateFormat.y(locale).format(dt),
      DatePrecision.timestamp =>
        '${DateFormat.yMMMd(locale).format(dt)} ${context.formatTime(dt)}',
    };
  }
}
