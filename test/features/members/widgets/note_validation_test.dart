import 'package:flutter_test/flutter_test.dart';

/// Mirrors the validation logic from NoteSheet:
/// `_isValid => _titleController.text.trim().isNotEmpty || _bodyController.text.trim().isNotEmpty`
bool isValid(String title, String body) =>
    title.trim().isNotEmpty || body.trim().isNotEmpty;

void main() {
  group('Note validation (title OR body required)', () {
    test('valid when title only', () {
      expect(isValid('Title', ''), true);
    });

    test('valid when body only', () {
      expect(isValid('', 'Body'), true);
    });

    test('valid when both present', () {
      expect(isValid('Title', 'Body'), true);
    });

    test('invalid when both empty', () {
      expect(isValid('', ''), false);
    });

    test('invalid when both whitespace only', () {
      expect(isValid('  ', '  '), false);
    });

    test('valid when title is whitespace but body has content', () {
      expect(isValid('   ', 'Some body text'), true);
    });

    test('valid when body is whitespace but title has content', () {
      expect(isValid('My title', '   '), true);
    });
  });
}
