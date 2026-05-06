import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

void main() {
  group('custom field value key normalization', () {
    test('extracts member-info key aliases from users[*].fields', () {
      expect(
        extractSpCustomFieldValueKeyMap({
          'opaque-a': {'name': 'cf-role'},
          'opaque-b': {'name': 'cf-age'},
          'skip-empty': {'name': ''},
          'skip-null': {},
        }),
        {'opaque-a': 'cf-role', 'opaque-b': 'cf-age'},
      );
    });

    test('normalizes member info keys before member parsing', () {
      final member = SpMember.fromJson(
        normalizeSpMemberJsonInfoKeys({
          '_id': 'm1',
          'name': 'Kai',
          'info': {'opaque-a': 'protector', 'cf-age': '27'},
        }, {
          'opaque-a': 'cf-role',
        }),
      );

      expect(member.info, {'cf-role': 'protector', 'cf-age': '27'});
    });

    test('SpParser.parse applies users[*].fields alias mapping to members', () {
      final data = SpParser.parse('''
      {
        "users": [
          {
            "uid": "sys1",
            "username": "test",
            "fields": {
              "opaque-a": {"name": "cf-role"},
              "opaque-b": {"name": "cf-age"}
            }
          }
        ],
        "members": [
          {
            "_id": "m1",
            "name": "Kai",
            "info": {
              "opaque-a": "protector",
              "opaque-b": "27"
            }
          }
        ]
      }
      ''');

      expect(data.members.single.info, {
        'cf-role': 'protector',
        'cf-age': '27',
      });
    });
  });

  group('SpMember.fromJson', () {
    test('parses members[*].info maps for custom field values', () {
      final member = SpMember.fromJson({
        '_id': 'm1',
        'name': 'Kai',
        'info': {
          'cf-text': 'Blue',
          'cf-bool': true,
          'cf-list': ['alpha', 'beta'],
        },
      });

      expect(member.id, 'm1');
      expect(member.info, {
        'cf-text': 'Blue',
        'cf-bool': true,
        'cf-list': ['alpha', 'beta'],
      });
    });

    test('falls back to an empty info map for non-map payloads', () {
      final member = SpMember.fromJson({
        '_id': 'm1',
        'name': 'Kai',
        'info': ['not', 'a', 'map'],
      });

      expect(member.info, isEmpty);
    });
  });

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
      final note = SpNote.fromJson({'_id': 'n1', 'note': 'Body'});

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
      expect(strEpoch.time, DateTime.fromMillisecondsSinceEpoch(1700000000000));

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

    test('falls back to createdAt and preserves off-scope collections', () {
      final comment = SpComment.fromJson({
        '_id': 'c4',
        'documentId': 'member-1',
        'collection': 'members',
        'comment': 'Profile note',
        'createdAt': 1700000000000,
      });

      expect(comment.collection, 'members');
      expect(comment.text, 'Profile note');
      expect(comment.time, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });
  });

  group('SpCustomFieldDef.fromJson', () {
    test('parses id, name, type', () {
      final field = SpCustomFieldDef.fromJson({
        '_id': 'f1',
        'name': 'Favorite Color',
        'type': 1,
      });

      expect(field.id, 'f1');
      expect(field.name, 'Favorite Color');
      expect(field.type, 1);
    });

    test('defaults type to 0 when missing', () {
      final field = SpCustomFieldDef.fromJson({'_id': 'f1', 'name': 'Notes'});

      expect(field.type, 0);
    });

    test('defaults name to "Field" when missing', () {
      final field = SpCustomFieldDef.fromJson({'_id': 'f1', 'type': 0});

      expect(field.name, 'Field');
    });

    test('parses supportMarkdown flag', () {
      final field = SpCustomFieldDef.fromJson({
        '_id': 'f1',
        'name': 'Notes',
        'type': 0,
        'supportMarkdown': true,
      });

      expect(field.supportMarkdown, isTrue);
    });
  });

  group('SpPoll.fromJson', () {
    test('parses standard poll flags and votes', () {
      final poll = SpPoll.fromJson({
        '_id': 'p1',
        'name': 'Test poll',
        'custom': false,
        'allowAbstain': true,
        'allowVeto': true,
        'votes': [
          {'id': 'mem1', 'vote': 'yes', 'comment': 'hell yea'},
        ],
      });

      expect(poll.id, 'p1');
      expect(poll.question, 'Test poll');
      expect(poll.isCustom, isFalse);
      expect(poll.allowAbstain, isTrue);
      expect(poll.allowVeto, isTrue);
      expect(poll.votes, hasLength(1));
      expect(poll.votes.first.optionName, 'yes');
    });

    test('parses multi-select polls with text-based options and endTime', () {
      final poll = SpPoll.fromJson({
        '_id': 'p2',
        'question': 'Pick two',
        'custom': true,
        'allowMultiple': true,
        'options': [
          {'text': 'Alpha', 'color': '#AA0000'},
          {'name': 'Beta', 'color': '#00BB00'},
        ],
        'votes': [
          {'id': 'mem1', 'vote': 'Alpha'},
          {'id': 'mem1', 'vote': 'Beta'},
        ],
        'endTime': '1700000000000',
      });

      expect(poll.question, 'Pick two');
      expect(poll.isCustom, isTrue);
      expect(poll.allowMultiple, isTrue);
      expect(poll.options.map((o) => o.name).toList(), ['Alpha', 'Beta']);
      expect(poll.options.map((o) => o.color).toList(), ['#AA0000', '#00BB00']);
      expect(poll.votes, hasLength(2));
      expect(poll.endDate, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });
  });

  group('SpBoardMessage.fromJson', () {
    test(
      'parses all fields including nullable writtenBy, writtenFor, title',
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
          msg.writtenAt,
          DateTime.fromMillisecondsSinceEpoch(1700000000000),
        );
      },
    );

    test('handles various timestamp formats', () {
      // Integer epoch
      final intTime = SpBoardMessage.fromJson({
        '_id': 'bm1',
        'message': 'Test',
        'writtenAt': 1700000000000,
      });
      expect(
        intTime.writtenAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      // String-encoded epoch
      final strEpoch = SpBoardMessage.fromJson({
        '_id': 'bm2',
        'message': 'Test',
        'writtenAt': '1700000000000',
      });
      expect(
        strEpoch.writtenAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

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
      expect(
        fallback.writtenAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
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

    test('parses read state used for board inbox migration', () {
      final msg = SpBoardMessage.fromJson({
        '_id': 'bm5',
        'writtenFor': 'member-b',
        'message': 'Seen already',
        'writtenAt': 1700000000000,
        'read': true,
      });

      expect(msg.read, isTrue);
    });
  });
}
