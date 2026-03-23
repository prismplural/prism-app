import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

void main() {
  group('SpNote.fromJson', () {
    test('parses int timestamp (epoch milliseconds)', () {
      final note = SpNote.fromJson({
        '_id': 'n1',
        'title': 'Test',
        'note': 'Body text',
        'date': 1700000000000,
      });

      expect(note.date, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('parses string-encoded timestamp', () {
      final note = SpNote.fromJson({
        '_id': 'n1',
        'title': 'Test',
        'note': 'Body',
        'date': '1700000000000',
      });

      expect(note.date, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('parses ISO date string', () {
      final note = SpNote.fromJson({
        '_id': 'n1',
        'title': 'Test',
        'note': 'Body',
        'date': '2023-11-14T22:13:20.000Z',
      });

      expect(note.date, DateTime.parse('2023-11-14T22:13:20.000Z'));
    });

    test('uses "note" field for body (fallback to "body")', () {
      final withNote = SpNote.fromJson({
        '_id': 'n1',
        'title': 'T',
        'note': 'From note field',
      });
      expect(withNote.body, 'From note field');

      final withBody = SpNote.fromJson({
        '_id': 'n2',
        'title': 'T',
        'body': 'From body field',
      });
      expect(withBody.body, 'From body field');
    });

    test('uses "_id" field (fallback to "id")', () {
      final withUnderscoreId = SpNote.fromJson({
        '_id': 'abc123',
        'title': 'T',
        'note': 'B',
      });
      expect(withUnderscoreId.id, 'abc123');

      final withId = SpNote.fromJson({
        'id': 'def456',
        'title': 'T',
        'note': 'B',
      });
      expect(withId.id, 'def456');
    });

    test('handles missing optional fields (color, memberId)', () {
      final note = SpNote.fromJson({
        '_id': 'n1',
        'title': 'Test',
        'note': 'Body',
      });

      expect(note.color, isNull);
      expect(note.memberId, isNull);
    });

    test('defaults title to "Untitled" when missing', () {
      final note = SpNote.fromJson({
        '_id': 'n1',
        'note': 'Body',
      });

      expect(note.title, 'Untitled');
    });
  });

  group('SpComment.fromJson', () {
    test('parses all fields correctly', () {
      final comment = SpComment.fromJson({
        '_id': 'c1',
        'documentId': 'doc-abc',
        'collection': 'frontHistory',
        'text': 'A comment',
        'time': 1700000000000,
      });

      expect(comment.id, 'c1');
      expect(comment.documentId, 'doc-abc');
      expect(comment.collection, 'frontHistory');
      expect(comment.text, 'A comment');
      expect(comment.time, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('handles "text" field (fallback to "comment")', () {
      final withText = SpComment.fromJson({
        '_id': 'c1',
        'documentId': 'd1',
        'collection': 'frontHistory',
        'text': 'From text field',
        'time': 1700000000000,
      });
      expect(withText.text, 'From text field');

      final withComment = SpComment.fromJson({
        '_id': 'c2',
        'documentId': 'd1',
        'collection': 'frontHistory',
        'comment': 'From comment field',
        'time': 1700000000000,
      });
      expect(withComment.text, 'From comment field');
    });

    test('parses various timestamp formats', () {
      // Integer epoch
      final intTime = SpComment.fromJson({
        '_id': 'c1',
        'documentId': 'd1',
        'collection': 'col',
        'text': 'T',
        'time': 1700000000000,
      });
      expect(intTime.time, DateTime.fromMillisecondsSinceEpoch(1700000000000));

      // String-encoded epoch
      final strEpoch = SpComment.fromJson({
        '_id': 'c2',
        'documentId': 'd1',
        'collection': 'col',
        'text': 'T',
        'time': '1700000000000',
      });
      expect(
          strEpoch.time, DateTime.fromMillisecondsSinceEpoch(1700000000000));

      // ISO date string
      final iso = SpComment.fromJson({
        '_id': 'c3',
        'documentId': 'd1',
        'collection': 'col',
        'text': 'T',
        'time': '2023-11-14T22:13:20.000Z',
      });
      expect(iso.time, DateTime.parse('2023-11-14T22:13:20.000Z'));
    });
  });

  group('SpCustomFieldDef.fromJson', () {
    test('parses id, name, type', () {
      final field = SpCustomFieldDef.fromJson({
        '_id': 'f1',
        'name': 'Favorite Color',
        'type': 'color',
      });

      expect(field.id, 'f1');
      expect(field.name, 'Favorite Color');
      expect(field.type, 'color');
    });

    test('defaults type to "text" when missing', () {
      final field = SpCustomFieldDef.fromJson({
        '_id': 'f1',
        'name': 'Notes',
      });

      expect(field.type, 'text');
    });

    test('defaults name to "Field" when missing', () {
      final field = SpCustomFieldDef.fromJson({
        '_id': 'f1',
        'type': 'text',
      });

      expect(field.name, 'Field');
    });
  });

  group('SpBoardMessage.fromJson', () {
    test('parses all fields including nullable writtenBy, writtenFor, title',
        () {
      final msg = SpBoardMessage.fromJson({
        '_id': 'bm1',
        'writtenBy': 'member-a',
        'writtenFor': 'member-b',
        'title': 'Hello',
        'message': 'Hi there!',
        'writtenAt': 1700000000000,
      });

      expect(msg.id, 'bm1');
      expect(msg.writtenBy, 'member-a');
      expect(msg.writtenFor, 'member-b');
      expect(msg.title, 'Hello');
      expect(msg.message, 'Hi there!');
      expect(
          msg.writtenAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('handles various timestamp formats', () {
      // Integer epoch
      final intTime = SpBoardMessage.fromJson({
        '_id': 'bm1',
        'message': 'Test',
        'writtenAt': 1700000000000,
      });
      expect(intTime.writtenAt,
          DateTime.fromMillisecondsSinceEpoch(1700000000000));

      // String-encoded epoch
      final strEpoch = SpBoardMessage.fromJson({
        '_id': 'bm2',
        'message': 'Test',
        'writtenAt': '1700000000000',
      });
      expect(strEpoch.writtenAt,
          DateTime.fromMillisecondsSinceEpoch(1700000000000));

      // ISO date string
      final iso = SpBoardMessage.fromJson({
        '_id': 'bm3',
        'message': 'Test',
        'writtenAt': '2023-11-14T22:13:20.000Z',
      });
      expect(iso.writtenAt, DateTime.parse('2023-11-14T22:13:20.000Z'));

      // Fallback to createdAt
      final fallback = SpBoardMessage.fromJson({
        '_id': 'bm4',
        'message': 'Test',
        'createdAt': 1700000000000,
      });
      expect(fallback.writtenAt,
          DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('defaults message to empty string when missing', () {
      final msg = SpBoardMessage.fromJson({
        '_id': 'bm1',
        'writtenAt': 1700000000000,
      });

      expect(msg.message, '');
    });

    test('nullable fields are null when absent', () {
      final msg = SpBoardMessage.fromJson({
        '_id': 'bm1',
        'message': 'Test',
        'writtenAt': 1700000000000,
      });

      expect(msg.writtenBy, isNull);
      expect(msg.writtenFor, isNull);
      expect(msg.title, isNull);
    });
  });
}
