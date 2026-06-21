import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:prism_plurality/domain/models/member.dart';
import 'package:prism_plurality/features/members/services/markdown_table_parser.dart';
import 'package:prism_plurality/shared/widgets/markdown_text.dart';

/// Renders a GFM [TableData] as a Flutter [Table] with per-column widths so an
/// image column hugs its image while text columns flex and wrap — something
/// flutter_markdown can't express (it applies one width rule to the whole
/// table).
///
/// Each cell is rendered by the normal [MarkdownText] renderer on the cell's
/// raw markdown, reusing inline text/bold/links/image (`#WxH` / `#%`) handling.
class PrismMarkdownTable extends StatelessWidget {
  const PrismMarkdownTable({
    super.key,
    required this.table,
    this.imgElementBuilder,
    this.baseStyle,
    this.memberMap,
    this.onTapMember,
    this.borderless = false,
    this.borderColor,
    this.textAlign,
  });

  final TableData table;

  /// Custom `img` element builder passed through to each cell's [MarkdownText].
  final MarkdownElementBuilder? imgElementBuilder;

  /// Base text style for cell body text.
  final TextStyle? baseStyle;

  /// Members used to resolve durable `@[uuid]` tokens in table cells.
  final Map<String, Member>? memberMap;

  /// Called when a resolved member mention is tapped in a table cell.
  final ValueChanged<String>? onTapMember;

  /// No borders + neutral header (matches `:::plain`).
  final bool borderless;

  /// Border color (ignored when [borderless]); null → theme divider color.
  final Color? borderColor;

  /// Fallback text alignment for cells without GFM column alignment.
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final rows = table.rows;
    if (rows.isEmpty) return const SizedBox.shrink();

    final colCount = rows.fold<int>(
      0,
      (max, r) => r.length > max ? r.length : max,
    );
    if (colCount == 0) return const SizedBox.shrink();

    final widths = _columnWidths(rows, colCount);

    return Table(
      columnWidths: widths,
      border: _border(context),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (var r = 0; r < rows.length; r++)
          TableRow(
            children: [
              for (var c = 0; c < colCount; c++)
                _cell(
                  context,
                  cell: c < rows[r].length ? rows[r][c] : '',
                  isHeader: r == 0,
                  align:
                      (c < table.aligns.length ? table.aligns[c] : null) ??
                      textAlign,
                  // Only intrinsic-width (image-hug) columns are measured, so
                  // only they need the finite-width guard.
                  hug: widths[c] is IntrinsicColumnWidth,
                ),
            ],
          ),
      ],
    );
  }

  /// IntrinsicColumnWidth for columns where every non-empty cell is an image
  /// (so they hug), FlexColumnWidth otherwise (so text/mixed columns flex).
  Map<int, TableColumnWidth> _columnWidths(
    List<List<String>> rows,
    int colCount,
  ) {
    // Inspect the body rows so a header label like "Avatar" doesn't force a
    // column to flex. But layout tables (image-beside-text) are usually written
    // header-only — a content row + separator, no body — so when there's no
    // body, fall back to the header row (otherwise we'd see no image cells and
    // make every column flex → 50/50).
    final dataRows = rows.length > 1 ? rows.sublist(1) : rows;

    final widths = <int, TableColumnWidth>{};
    for (var c = 0; c < colCount; c++) {
      var sawCell = false;
      var allImages = true;
      for (final row in dataRows) {
        final cell = c < row.length ? row[c].trim() : '';
        if (cell.isEmpty) continue;
        sawCell = true;
        if (!cell.contains('![')) {
          allImages = false;
          break;
        }
      }
      widths[c] = (sawCell && allImages)
          ? const IntrinsicColumnWidth()
          : const FlexColumnWidth();
    }
    return widths;
  }

  TableBorder? _border(BuildContext context) {
    if (borderless) return const TableBorder();
    if (borderColor != null) return TableBorder.all(color: borderColor!);
    return TableBorder.all(color: Theme.of(context).dividerColor);
  }

  Widget _cell(
    BuildContext context, {
    required String cell,
    required bool isHeader,
    required TextAlign? align,
    required bool hug,
  }) {
    // Header is bold unless borderless (plain layout tables keep a neutral head).
    final bold = isHeader && !borderless;
    var style = baseStyle ?? const TextStyle();
    if (bold) style = style.copyWith(fontWeight: FontWeight.bold);

    // Bordered/colored tables get roomier cell padding so content (esp. an
    // image) doesn't sit against the border lines. Borderless tables stay tight
    // so image-beside-text still lines up with surrounding bio text.
    final padding = borderless
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);

    final content = MarkdownText(
      data: cell,
      imgElementBuilder: imgElementBuilder,
      baseStyle: style,
      memberMap: memberMap,
      onTapMember: onTapMember,
      textAlign: align,
    );

    return TableCell(
      child: Padding(
        padding: padding,
        child: Align(
          alignment: _alignment(align),
          child: hug ? _SafeIntrinsicWidth(child: content) : content,
        ),
      ),
    );
  }

  AlignmentGeometry _alignment(TextAlign? align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.topCenter;
      case TextAlign.right:
      case TextAlign.end:
        return Alignment.topRight;
      default:
        return Alignment.topLeft;
    }
  }
}

/// Reports a finite max-intrinsic width so a [Table]'s [IntrinsicColumnWidth]
/// column can't be crashed by a cell that measures as non-finite (an `Image`
/// laid out at infinite width) or throws when measured (a `LayoutBuilder`).
/// A finite child measurement passes through, so a normal image still hugs.
class _SafeIntrinsicWidth extends SingleChildRenderObjectWidget {
  const _SafeIntrinsicWidth({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSafeIntrinsicWidth();
}

class _RenderSafeIntrinsicWidth extends RenderProxyBox {
  /// Width used when a child can't be measured.
  static const double _fallbackWidth = 280.0;

  double _finiteOr(double Function() compute) {
    final double value;
    try {
      value = compute();
    } catch (_) {
      return _fallbackWidth;
    }
    return value.isFinite ? value : _fallbackWidth;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _finiteOr(() => super.computeMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _finiteOr(() => super.computeMaxIntrinsicWidth(height));
}
