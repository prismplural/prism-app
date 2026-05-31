/// Builds GFM table markdown (optionally wrapped in Prism's `:::` styling fence)
/// ready for insertion into a long-text editor. Pure: no widget/editor state.
///
/// [columns] is the number of columns. [rows] is the number of content rows the
/// user asked for. Cells are emitted EMPTY for the user to fill in afterward.
///
/// GFM always requires a header row, so [headerRow] controls structure rather
/// than presence:
///   - true  -> a dedicated (empty) header row is emitted ABOVE [rows] body
///              rows ([rows] + 1 cell rows total).
///   - false -> no dedicated header; the first content row doubles as the
///              structurally-required header row, so exactly [rows] cell rows
///              are emitted.
///
/// Border treatment maps onto the three modes the renderer supports
/// (prism_markdown_table.dart / bio_markdown_segments.dart):
///   - [showBorders] false            -> wrapped in `:::plain` (no borders)
///   - [showBorders] true, no color   -> bare GFM (theme divider borders)
///   - [showBorders] true, with color -> wrapped in `:::#RRGGBB`
///
/// Cell-content note: cells are empty today. Any future caller emitting
/// non-empty cell text MUST escape literal `|` as `\|` (see
/// markdown_table_parser `_splitCells`), or the column structure will break.
String buildTableMarkdown({
  required int columns,
  required int rows,
  required bool headerRow,
  required bool showBorders,
  String? borderColorHex,
}) {
  final cols = columns < 1 ? 1 : columns;
  final wantRows = rows < 1 ? 1 : rows;

  // Empty cell is two spaces so a row reads as `|  |  |` — it must contain pipes
  // for the parser's row detection (markdown_table_parser `_looksLikeTableRow`).
  final emptyRow = '|${List.filled(cols, '  ').join('|')}|';
  final separator = '|${List.filled(cols, ' --- ').join('|')}|';

  // header on  -> dedicated header + wantRows body rows
  // header off -> wantRows total, row 0 doubling as the required header
  final bodyCount = headerRow ? wantRows : wantRows - 1;
  final lines = <String>[
    emptyRow,
    separator,
    for (var i = 0; i < bodyCount; i++) emptyRow,
  ];
  final table = lines.join('\n');

  if (!showBorders) return ':::plain\n$table\n:::';

  final hex = borderColorHex == null ? null : _normalizeHex(borderColorHex);
  if (hex != null) return ':::$hex\n$table\n:::';

  return table;
}

/// Uppercase, `#`-prefixed hex. Accepts `RRGGBB` or `#RRGGBB` (and the 3/8-digit
/// forms); the renderer's `parseHexColor` handles `#RGB`/`#RRGGBB`/`#AARRGGBB`.
String _normalizeHex(String hex) {
  final h = hex.trim();
  final withHash = h.startsWith('#') ? h : '#$h';
  return withHash.toUpperCase();
}
