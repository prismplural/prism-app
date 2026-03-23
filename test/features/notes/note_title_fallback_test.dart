import 'package:flutter_test/flutter_test.dart';

/// Mirrors the display title logic used in _NoteCard and NoteDetailScreen.
String displayTitle(String title, String body) {
  if (title.isNotEmpty) return title;
  final firstLine = body.split('\n').first.trim();
  if (firstLine.isNotEmpty) return firstLine;
  return 'Untitled';
}

void main() {
  group('Note title fallback logic', () {
    test('shows title when present', () {
      expect(displayTitle('My Note', 'some body'), 'My Note');
    });

    test('shows first line of body when title is empty', () {
      expect(displayTitle('', 'Hello world'), 'Hello world');
    });

    test('shows Untitled when title empty and body starts with newline', () {
      // '\nHello'.split('\n') => ['', 'Hello'], first is '', trimmed is ''
      expect(displayTitle('', '\nHello'), 'Untitled');
    });

    test('shows Untitled when both title and body are empty', () {
      expect(displayTitle('', ''), 'Untitled');
    });

    test('shows Untitled when title empty and body is whitespace only', () {
      expect(displayTitle('', '  \n  '), 'Untitled');
    });

    test('shows first line when body has multiple lines', () {
      expect(displayTitle('', 'First line\nSecond line'), 'First line');
    });

    test('trims whitespace from first line of body', () {
      expect(displayTitle('', '  Padded  \nother'), 'Padded');
    });
  });
}
