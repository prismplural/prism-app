import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/shared/utils/markdown_cursor_insert.dart';

void main() {
  group('insertMarkdownAtCursor', () {
    test('inserts at a collapsed cursor and moves the caret after the insert',
        () {
      final c = TextEditingController(text: 'abcd');
      c.selection = const TextSelection.collapsed(offset: 2);
      insertMarkdownAtCursor(c, 'XY');
      expect(c.text, 'abXYcd');
      expect(c.selection.baseOffset, 4);
    });

    test('replaces the selected range', () {
      final c = TextEditingController(text: 'abcd');
      c.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
      insertMarkdownAtCursor(c, 'Z');
      expect(c.text, 'aZd');
      expect(c.selection.baseOffset, 2);
    });

    test('appends when there is no selection', () {
      final c = TextEditingController(text: 'abc'); // default selection is -1
      insertMarkdownAtCursor(c, '!');
      expect(c.text, 'abc!');
    });
  });

  group('padBlockForInsertion', () {
    TextEditingController at(String text, int offset) =>
        TextEditingController(text: text)
          ..selection = TextSelection.collapsed(offset: offset);

    test('no leading pad at an empty field start; trailing newline at EOF', () {
      expect(padBlockForInsertion(at('', 0), 'B'), 'B\n');
    });

    test('blank line before non-newline text; trailing newline at EOF', () {
      expect(padBlockForInsertion(at('hello', 5), 'B'), '\n\nB\n');
    });

    test('a single trailing newline gets one more to make a blank line', () {
      expect(padBlockForInsertion(at('hello\n', 6), 'B'), '\nB\n');
    });

    test('an existing blank line needs no leading pad', () {
      expect(padBlockForInsertion(at('hello\n\n', 7), 'B'), 'B\n');
    });

    test('mid-line insertion pads both sides (excludes surrounding text)', () {
      expect(padBlockForInsertion(at('abcd', 2), 'B'), '\n\nB\n\n');
    });
  });
}
