import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:prism_plurality/features/members/services/markdown_table_builder.dart';
import 'package:prism_plurality/shared/extensions/app_localizations_extension.dart';
import 'package:prism_plurality/shared/utils/markdown_cursor_insert.dart';
import 'package:prism_plurality/shared/widgets/prism_button.dart';
import 'package:prism_plurality/shared/widgets/prism_color_picker_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_dialog.dart';
import 'package:prism_plurality/shared/widgets/prism_switch_row.dart';
import 'package:prism_plurality/shared/widgets/prism_top_bar_action.dart';

/// A button that inserts a markdown table into [controller] at the cursor.
///
/// Opens a small dialog to choose dimensions, whether to include a header row,
/// and border styling (none / theme / custom color), then writes the generated
/// markdown (`buildTableMarkdown`) at the cursor via the shared insert helper.
///
/// Sits next to [MarkdownImageButton] in the long-text editors (notes, custom
/// fields, board posts). Unlike the image button it needs no image session —
/// tables are pure text.
class MarkdownTableButton extends StatelessWidget {
  const MarkdownTableButton({super.key, required this.controller});

  /// The text field whose content receives the inserted table markdown.
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return PrismTopBarAction(
      icon: PhosphorIcons.table(),
      tooltip: context.l10n.tableInsertTooltip,
      onPressed: () => _open(context),
    );
  }

  Future<void> _open(BuildContext context) async {
    final nav = Navigator.of(context, rootNavigator: true);
    final l10n = context.l10n;

    // Closure-held form state so the action buttons can read the latest spec.
    var spec = const TableSpec();

    final confirmed = await PrismDialog.show<bool>(
      context: context,
      title: l10n.tableInsertTitle,
      builder: (_) =>
          _InsertTableForm(initial: spec, onChanged: (s) => spec = s),
      actions: [
        PrismButton(
          label: l10n.cancel,
          tone: PrismButtonTone.outlined,
          onPressed: () => nav.pop(false),
        ),
        PrismButton(
          label: l10n.tableInsertConfirm,
          tone: PrismButtonTone.filled,
          onPressed: () => nav.pop(true),
        ),
      ],
    );

    if (confirmed != true) return;

    final block = buildTableMarkdown(
      columns: spec.columns,
      rows: spec.rows,
      headerRow: spec.headerRow,
      showBorders: spec.showBorders,
      borderColorHex: spec.borderColorHex,
    );
    insertMarkdownAtCursor(controller, padBlockForInsertion(controller, block));
    await HapticFeedback.mediumImpact();
  }
}

/// Immutable form state for the insert-table dialog.
class TableSpec {
  const TableSpec({
    this.columns = 2,
    this.rows = 2,
    this.headerRow = true,
    this.showBorders = true,
    this.borderColorHex,
  });

  final int columns;
  final int rows;
  final bool headerRow;
  final bool showBorders;

  /// `#RRGGBB` custom border color, or null for the theme default border.
  final String? borderColorHex;

  TableSpec copyWith({
    int? columns,
    int? rows,
    bool? headerRow,
    bool? showBorders,
    String? borderColorHex,
    bool clearColor = false,
  }) {
    return TableSpec(
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      headerRow: headerRow ?? this.headerRow,
      showBorders: showBorders ?? this.showBorders,
      borderColorHex: clearColor
          ? null
          : (borderColorHex ?? this.borderColorHex),
    );
  }
}

const int _kMinColumns = 1;
const int _kMaxColumns = 8;
const int _kMinRows = 1;
const int _kMaxRows = 10;

class _InsertTableForm extends StatefulWidget {
  const _InsertTableForm({required this.initial, required this.onChanged});

  final TableSpec initial;
  final ValueChanged<TableSpec> onChanged;

  @override
  State<_InsertTableForm> createState() => _InsertTableFormState();
}

class _InsertTableFormState extends State<_InsertTableForm> {
  late TableSpec _spec = widget.initial;

  void _update(TableSpec next) {
    setState(() => _spec = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CounterRow(
          label: l10n.tableColumnsLabel,
          value: _spec.columns,
          min: _kMinColumns,
          max: _kMaxColumns,
          decrementTooltip: l10n.tableRemoveColumn,
          incrementTooltip: l10n.tableAddColumn,
          onChanged: (v) => _update(_spec.copyWith(columns: v)),
        ),
        _CounterRow(
          label: l10n.tableRowsLabel,
          value: _spec.rows,
          min: _kMinRows,
          max: _kMaxRows,
          decrementTooltip: l10n.tableRemoveRow,
          incrementTooltip: l10n.tableAddRow,
          onChanged: (v) => _update(_spec.copyWith(rows: v)),
        ),
        const Divider(height: 24),
        PrismSwitchRow(
          title: l10n.tableShowBordersLabel,
          value: _spec.showBorders,
          onChanged: (v) => _update(_spec.copyWith(showBorders: v)),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _spec.showBorders
              ? _BorderColorRow(
                  colorHex: _spec.borderColorHex,
                  onPick: (hex) => _update(
                    hex == null
                        ? _spec.copyWith(clearColor: true)
                        : _spec.copyWith(borderColorHex: hex),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const Divider(height: 24),
        PrismSwitchRow(
          title: l10n.tableHeaderRowLabel,
          subtitle: l10n.tableHeaderRowSubtitle,
          value: _spec.headerRow,
          onChanged: (v) => _update(_spec.copyWith(headerRow: v)),
        ),
        // A header row reads as one only with borders; hint when they're off.
        if (_spec.headerRow && !_spec.showBorders)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 16, right: 16),
            child: Text(
              l10n.tableHeaderRowPlainHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _CounterRow extends StatelessWidget {
  const _CounterRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.decrementTooltip,
    required this.incrementTooltip,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String decrementTooltip;
  final String incrementTooltip;
  final ValueChanged<int> onChanged;

  void _step(int delta) {
    HapticFeedback.selectionClick();
    onChanged((value + delta).clamp(min, max));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          IconButton(
            icon: Icon(PhosphorIcons.minus()),
            tooltip: decrementTooltip,
            onPressed: value > min ? () => _step(-1) : null,
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: Icon(PhosphorIcons.plus()),
            tooltip: incrementTooltip,
            onPressed: value < max ? () => _step(1) : null,
          ),
        ],
      ),
    );
  }
}

class _BorderColorRow extends StatelessWidget {
  const _BorderColorRow({required this.colorHex, required this.onPick});

  /// Current `#RRGGBB` color, or null for the theme default border.
  final String? colorHex;

  /// Called with the chosen `#RRGGBB`, or null if the user cancelled (kept).
  final ValueChanged<String?> onPick;

  Color _swatchColor(BuildContext context) {
    final hex = colorHex;
    if (hex == null) return Theme.of(context).colorScheme.primary;
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse('FF$cleaned', radix: 16);
    return value == null ? Theme.of(context).colorScheme.primary : Color(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final swatch = _swatchColor(context);
    final valueLabel = colorHex ?? l10n.tableBorderColorDefault;

    return InkWell(
      onTap: () async {
        final picked = await showPrismColorPickerDialog(
          context: context,
          initialColor: swatch,
          title: l10n.tableBorderColorLabel,
        );
        if (picked != null) onPick(picked);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.tableBorderColorLabel,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            Text(
              valueLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
