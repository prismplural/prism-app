/// Splits markdown into ordered blocks of either prose (raw markdown text) or a
/// parsed GFM table, so the host can render tables with per-column widths
/// (image columns hug, text columns flex) instead of flutter_markdown's single
/// whole-table column rule.
///
/// The markdown stays standard GFM — this is purely a structural pre-pass over
/// the text. Inline content inside each block (and each table cell) is still
/// rendered by the normal markdown renderer.
library;

import 'package:flutter/material.dart' show TextAlign;

/// One block of a markdown document: either prose [text] or a [table].
/// Exactly one of the two is non-null.
class MarkdownBlock {
  const MarkdownBlock.text(String this.text) : table = null;
  const MarkdownBlock.table(TableData this.table) : text = null;

  /// Raw markdown for a prose block (null for table blocks).
  final String? text;

  /// Parsed table data (null for prose blocks).
  final TableData? table;

  bool get isTable => table != null;
}

/// A parsed GFM table: a grid of RAW cell markdown strings plus per-column
/// alignment. `rows[0]` is the header row; the separator row is not stored.
class TableData {
  const TableData({required this.rows, required this.aligns});

  /// Cell markdown by row then column. `rows[0]` is the header.
  final List<List<String>> rows;

  /// Per-column [TextAlign] from the separator row, or null when unspecified.
  /// Indexed by column; may be shorter/longer than a given row's cell count.
  final List<TextAlign?> aligns;
}

/// Split [markdown] into ordered prose / table blocks.
///
/// A GFM table is a `|`-containing header line immediately followed by a
/// separator line whose cells contain only `-`, `:` and spaces, then zero or
/// more body rows until a blank line or a non-table line. Everything else is
/// emitted as prose text blocks (preserving original line content and order).
List<MarkdownBlock> splitMarkdownBlocks(String markdown) {
  final lines = markdown.split('\n');
  final blocks = <MarkdownBlock>[];
  final prose = <String>[];

  void flushProse() {
    if (prose.isEmpty) return;
    blocks.add(MarkdownBlock.text(prose.join('\n')));
    prose.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final header = lines[i];

    // Fenced code blocks (``` or ~~~) are copied verbatim into prose so that
    // pipe-table-looking lines inside them are never turned into real tables.
    final fence = _fenceOpen(header);
    if (fence != null) {
      prose.add(header);
      i += 1;
      while (i < lines.length) {
        final inner = lines[i];
        prose.add(inner);
        i += 1;
        if (_fenceCloses(inner, fence)) break;
      }
      // An unterminated fence just stays prose through EOF.
      continue;
    }

    final separator = i + 1 < lines.length ? lines[i + 1] : null;

    if (separator != null &&
        _looksLikeTableRow(header) &&
        _isSeparatorRow(separator)) {
      // Collect body rows until a blank/non-table line.
      var j = i + 2;
      final bodyLines = <String>[];
      while (j < lines.length && _looksLikeTableRow(lines[j])) {
        bodyLines.add(lines[j]);
        j += 1;
      }

      flushProse();
      final aligns = _parseAligns(separator);
      final rows = <List<String>>[
        _splitCells(header),
        for (final line in bodyLines) _splitCells(line),
      ];
      blocks.add(MarkdownBlock.table(TableData(rows: rows, aligns: aligns)));
      i = j;
      continue;
    }

    prose.add(header);
    i += 1;
  }

  flushProse();
  return blocks;
}

/// Describes an opening code fence: its fence character (`` ` `` or `~`) and the
/// number of consecutive fence characters that opened it.
class _FenceOpen {
  const _FenceOpen(this.char, this.length);

  final String char;
  final int length;
}

/// If [line] opens a code fence (its leading non-whitespace run is three or more
/// backticks or three or more tildes), returns the [_FenceOpen]; otherwise null.
///
/// Per CommonMark, the fence run must be the leading run of fence characters on
/// the line (an info string after the run is allowed and ignored here).
_FenceOpen? _fenceOpen(String line) {
  final trimmed = line.trimLeft();
  if (trimmed.isEmpty) return null;
  final char = trimmed[0];
  if (char != '`' && char != '~') return null;
  var length = 0;
  while (length < trimmed.length && trimmed[length] == char) {
    length += 1;
  }
  if (length < 3) return null;
  return _FenceOpen(char, length);
}

/// Returns true if [line] closes the fence described by [open]: the trimmed line
/// must consist solely of [open] characters repeated at least [open.length]
/// times (CommonMark allows a longer closing fence, but not a shorter one).
bool _fenceCloses(String line, _FenceOpen open) {
  final trimmed = line.trim();
  if (trimmed.length < open.length) return false;
  for (var j = 0; j < trimmed.length; j += 1) {
    if (trimmed[j] != open.char) return false;
  }
  return true;
}

/// A line that could be a table row: contains an unescaped `|`.
bool _looksLikeTableRow(String line) {
  if (line.trim().isEmpty) return false;
  for (var i = 0; i < line.length; i++) {
    if (line[i] == '|' && (i == 0 || line[i - 1] != '\\')) return true;
  }
  return false;
}

/// A separator row: at least one cell, every cell only `-`/`:`/spaces with at
/// least one `-`.
bool _isSeparatorRow(String line) {
  if (!_looksLikeTableRow(line)) return false;
  final cells = _splitCells(line);
  if (cells.isEmpty) return false;
  for (final cell in cells) {
    final c = cell.trim();
    if (c.isEmpty) return false;
    if (!RegExp(r'^:?-+:?$').hasMatch(c)) return false;
  }
  return true;
}

/// Per-column [TextAlign] from a separator row (`:--`=left, `:-:`=center,
/// `--:`=right, otherwise null).
List<TextAlign?> _parseAligns(String separator) {
  return _splitCells(separator).map((cell) {
    final c = cell.trim();
    final left = c.startsWith(':');
    final right = c.endsWith(':');
    if (left && right) return TextAlign.center;
    if (right) return TextAlign.right;
    if (left) return TextAlign.left;
    return null;
  }).toList();
}

/// Split a table row into trimmed cell strings, honoring optional leading and
/// trailing pipes and not splitting on escaped `\|`.
List<String> _splitCells(String line) {
  var s = line.trim();
  // Strip a single optional leading/trailing pipe (unescaped).
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|') && !s.endsWith('\\|')) {
    s = s.substring(0, s.length - 1);
  }

  final cells = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '\\' && i + 1 < s.length && s[i + 1] == '|') {
      // Preserve the escaped pipe verbatim so downstream markdown sees `\|`.
      buf.write('\\|');
      i += 1;
      continue;
    }
    if (ch == '|') {
      cells.add(buf.toString().trim());
      buf.clear();
      continue;
    }
    buf.write(ch);
  }
  cells.add(buf.toString().trim());
  return cells;
}
