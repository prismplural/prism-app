import 'package:flutter/material.dart';

/// Inserts [markdown] into [controller] at the current selection, replacing any
/// selected range, and collapses the cursor just after the inserted text. When
/// there is no valid selection (offset < 0), the text is appended at the end.
///
/// Shared by the long-text editor affordances (image button, table button) so
/// insertion behaves identically across them.
void insertMarkdownAtCursor(TextEditingController controller, String markdown) {
  final sel = controller.selection;
  final text = controller.text;
  final start = sel.start < 0 ? text.length : sel.start;
  final end = sel.end < 0 ? text.length : sel.end;
  controller.value = controller.value.copyWith(
    text: text.replaceRange(start, end, markdown),
    selection: TextSelection.collapsed(offset: start + markdown.length),
  );
}

/// Pads a block-level [block] (e.g. a `:::` fence or a GFM table) so it lands on
/// its own line(s) when inserted at the cursor in [controller]: a blank line is
/// ensured before it (unless it would sit at the very start of the field) and
/// after it (unless at the very end). Block-level markdown must begin at the
/// start of a line to be recognized, and GFM tables need a blank line
/// separating them from surrounding prose.
String padBlockForInsertion(TextEditingController controller, String block) {
  final sel = controller.selection;
  final text = controller.text;
  final start = sel.start < 0 ? text.length : sel.start;
  final end = sel.end < 0 ? text.length : sel.end;
  return '${_leadingPad(text, start)}$block${_trailingPad(text, end)}';
}

String _leadingPad(String text, int start) {
  if (start <= 0) return '';
  final before = text[start - 1];
  if (before != '\n') return '\n\n'; // mid-line: line break + blank line
  final before2 = start >= 2 ? text[start - 2] : null;
  return (before2 == null || before2 == '\n') ? '' : '\n'; // ensure blank line
}

String _trailingPad(String text, int end) {
  if (end >= text.length) {
    // at EOF: add a newline so the caret lands below the block, not on its last row
    return '\n';
  }
  final after = text[end];
  if (after != '\n') return '\n\n';
  final after2 = end + 1 < text.length ? text[end + 1] : null;
  return (after2 == null || after2 == '\n') ? '' : '\n';
}
