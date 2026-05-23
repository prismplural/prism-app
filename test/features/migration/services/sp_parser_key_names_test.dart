import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';

void main() {
  group('SpParser key-name compatibility', () {
    test('parses customFronts from frontStatuses key', () {
      final json = jsonEncode({
        'members': [],
        'frontStatuses': [
          {'_id': 'cf1', 'name': 'Co-fronting', 'color': '#ff0000'},
        ],
        'frontHistory': [],
      });
      final data = SpParser.parse(json);
      expect(data.customFronts.length, 1);
      expect(data.customFronts.first.name, 'Co-fronting');
    });

    test('parses customFronts from customFronts key (backward compat)', () {
      final json = jsonEncode({
        'members': [],
        'customFronts': [
          {'_id': 'cf1', 'name': 'Blurry'},
        ],
        'frontHistory': [],
      });
      final data = SpParser.parse(json);
      expect(data.customFronts.length, 1);
      expect(data.customFronts.first.name, 'Blurry');
    });

    test('parses chat messages from flat chatMessages list', () {
      final json = jsonEncode({
        'members': [],
        'frontHistory': [],
        'chatMessages': [
          {
            '_id': 'msg1',
            'message': 'Hello',
            'channel': 'ch1',
            'writer': 'mem1',
            'writtenAt': 1774242087364,
          },
          {
            '_id': 'msg2',
            'message': 'Hi there',
            'channel': 'ch1',
            'writer': 'mem2',
            'writtenAt': 1774242090000,
          },
        ],
      });
      final data = SpParser.parse(json);
      expect(data.messages.length, 2);
      expect(data.messages.first.content, 'Hello');
      expect(data.messages.first.channelId, 'ch1');
      expect(data.messages.first.senderId, 'mem1');
    });

    test('detects old encrypted chat blobs and can drop chat data', () {
      final json = jsonEncode({
        'members': [
          {'_id': 'mem1', 'name': 'Alice'},
        ],
        'frontHistory': [],
        'channelCategories': [
          {
            '_id': 'cat1',
            'name': 'General',
            'channels': ['ch1'],
          },
        ],
        'channels': [
          {'_id': 'ch1', 'name': 'General'},
        ],
        'chatMessages': [
          {
            '_id': 'msg1',
            'message': 'rR9y0tk=',
            'iv': 'YWJjZGVmZ2hpamtsbW5vcA==',
            'channel': 'ch1',
            'writer': 'mem1',
            'writtenAt': 1774242087364,
          },
        ],
      });

      final data = SpParser.parse(json);
      expect(data.hasEncryptedChatMessages, isTrue);
      expect(data.encryptedChatMessageCount, 1);
      expect(data.messages.single.looksEncrypted, isTrue);

      final withoutChat = data.withoutChat();
      expect(withoutChat.members, hasLength(1));
      expect(withoutChat.channels, isEmpty);
      expect(withoutChat.channelCategories, isEmpty);
      expect(withoutChat.messages, isEmpty);
      expect(withoutChat.hasEncryptedChatMessages, isFalse);
    });

    test(
      'does not flag current plaintext chat exports that still include iv',
      () {
        final json = jsonEncode({
          'members': [],
          'frontHistory': [],
          'channels': [
            {'_id': 'ch1', 'name': 'General'},
          ],
          'chatMessages': [
            {
              '_id': 'msg1',
              'message': 'Readable Simply Plural export text',
              'iv': 'YWJjZGVmZ2hpamtsbW5vcA==',
              'channel': 'ch1',
              'writer': 'mem1',
              'writtenAt': 1774242087364,
            },
          ],
        });

        final data = SpParser.parse(json);
        expect(data.hasEncryptedChatMessages, isFalse);
        expect(data.messages.single.looksEncrypted, isFalse);
        expect(
          data.messages.single.content,
          'Readable Simply Plural export text',
        );
      },
    );

    test(
      'does not flag short plaintext messages that look like base64 tokens',
      () {
        final json = jsonEncode({
          'members': [],
          'frontHistory': [],
          'channels': [
            {'_id': 'ch1', 'name': 'General'},
          ],
          'chatMessages': [
            {
              '_id': 'msg1',
              'message': 'test',
              'iv': 'YWJjZGVmZ2hpamtsbW5vcA==',
              'channel': 'ch1',
              'writer': 'mem1',
              'writtenAt': 1774242087364,
            },
            {
              '_id': 'msg2',
              'message': 'yeah',
              'iv': 'YWJjZGVmZ2hpamtsbW5vcA==',
              'channel': 'ch1',
              'writer': 'mem1',
              'writtenAt': 1774242090000,
            },
          ],
        });

        final data = SpParser.parse(json);
        expect(data.hasEncryptedChatMessages, isFalse);
        expect(data.encryptedChatMessageCount, 0);
        expect(data.messages.map((m) => m.content), ['test', 'yeah']);
      },
    );

    test('parses chat messages from messages map (backward compat)', () {
      final json = jsonEncode({
        'members': [],
        'frontHistory': [],
        'messages': {
          'ch1': [
            {
              '_id': 'msg1',
              'message': 'Hello',
              'sender': 'mem1',
              'timestamp': 1774242087364,
            },
          ],
        },
      });
      final data = SpParser.parse(json);
      expect(data.messages.length, 1);
      expect(data.messages.first.channelId, 'ch1');
    });

    test('keeps boardMessages separate from chat messages', () {
      final json = jsonEncode({
        'members': [],
        'frontHistory': [],
        'boardMessages': [
          {
            '_id': 'bm1',
            'writtenBy': 'mem1',
            'writtenFor': 'mem2',
            'title': 'Hello',
            'message': 'Board body',
            'writtenAt': 1774242087364,
          },
        ],
      });
      final data = SpParser.parse(json);
      expect(data.messages, isEmpty);
      expect(data.boardMessages, hasLength(1));
      expect(data.boardMessages.first.id, 'bm1');
      expect(data.boardMessages.first.message, 'Board body');
    });

    test('parses automatedTimers from automatedReminders key', () {
      final json = jsonEncode({
        'members': [],
        'frontHistory': [],
        'automatedReminders': [
          {'_id': 'at1', 'name': 'Front check', 'delayInHours': 0.5},
        ],
      });
      final data = SpParser.parse(json);
      expect(data.automatedTimers.length, 1);
      expect(data.automatedTimers.first.name, 'Front check');
    });

    test('parses repeatedTimers from repeatedReminders key', () {
      final json = jsonEncode({
        'members': [],
        'frontHistory': [],
        'repeatedReminders': [
          {
            '_id': 'rt1',
            'name': 'Log your front!',
            'dayInterval': 1,
            'time': {'hour': 9, 'minute': 0},
          },
        ],
      });
      final data = SpParser.parse(json);
      expect(data.repeatedTimers.length, 1);
      expect(data.repeatedTimers.first.name, 'Log your front!');
    });

    test('handles SP typo key repeatedRemidners', () {
      final json = jsonEncode({
        'members': [],
        'frontHistory': [],
        'repeatedRemidners': [
          {'_id': 'rt1', 'name': 'Typo key timer'},
        ],
      });
      final data = SpParser.parse(json);
      expect(data.repeatedTimers.length, 1);
    });
  });

  group('SpFrontHistory.fromJson', () {
    test('reads custom flag from "custom" key', () {
      final fh = SpFrontHistory.fromJson({
        '_id': 'fh1',
        'member': 'mem1',
        'startTime': 1767362442459,
        'custom': true,
      });
      expect(fh.isCustomFront, true);
    });

    test('reads custom flag from "customFront" key (backward compat)', () {
      final fh = SpFrontHistory.fromJson({
        '_id': 'fh1',
        'member': 'mem1',
        'startTime': 1767362442459,
        'customFront': true,
      });
      expect(fh.isCustomFront, true);
    });

    test('defaults to false when no custom flag', () {
      final fh = SpFrontHistory.fromJson({
        '_id': 'fh1',
        'member': 'mem1',
        'startTime': 1767362442459,
      });
      expect(fh.isCustomFront, false);
    });
  });

  group('SpMessage.fromJson', () {
    test('reads sender from writer field', () {
      final msg = SpMessage.fromJson({
        '_id': 'msg1',
        'message': 'Hello',
        'writer': 'mem1',
        'writtenAt': 1774242087364,
      }, 'ch1');
      expect(msg.senderId, 'mem1');
    });

    test('reads timestamp from writtenAt field', () {
      final msg = SpMessage.fromJson({
        '_id': 'msg1',
        'message': 'Hello',
        'writer': 'mem1',
        'writtenAt': 1774242087364,
      }, 'ch1');
      expect(msg.timestamp.millisecondsSinceEpoch, 1774242087364);
    });

    test('falls back to sender and timestamp fields', () {
      final msg = SpMessage.fromJson({
        '_id': 'msg1',
        'message': 'Hello',
        'sender': 'mem1',
        'timestamp': 1774242087364,
      }, 'ch1');
      expect(msg.senderId, 'mem1');
      expect(msg.timestamp.millisecondsSinceEpoch, 1774242087364);
    });
  });

  group('SpRepeatedTimer.fromJson', () {
    test('reads dayInterval field', () {
      final rt = SpRepeatedTimer.fromJson({
        '_id': 'rt1',
        'name': 'Test',
        'dayInterval': 1,
      });
      expect(rt.intervalDays, 1);
    });

    test('reads time as map {hour, minute}', () {
      final rt = SpRepeatedTimer.fromJson({
        '_id': 'rt1',
        'name': 'Test',
        'time': {'hour': 9, 'minute': 0},
      });
      expect(rt.timeOfDay, '9:00');
    });

    test('reads time as string (backward compat)', () {
      final rt = SpRepeatedTimer.fromJson({
        '_id': 'rt1',
        'name': 'Test',
        'time': '9:00',
      });
      expect(rt.timeOfDay, '9:00');
    });
  });

  group('Firebase Timestamp tolerance', () {
    test('SpFrontHistory accepts Firebase Timestamp startTime', () {
      final fh = SpFrontHistory.fromJson({
        '_id': 'fh1',
        'member': 'mem1',
        'startTime': {'_seconds': 1684858400, '_nanoseconds': 123000000},
      });
      expect(fh.startTime.millisecondsSinceEpoch, 1684858400123);
    });

    test('SpFrontHistory accepts unprefixed seconds/nanoseconds', () {
      final fh = SpFrontHistory.fromJson({
        '_id': 'fh1',
        'member': 'mem1',
        'startTime': {'seconds': 1684858400, 'nanoseconds': 500000000},
      });
      expect(fh.startTime.millisecondsSinceEpoch, 1684858400500);
    });

    test('SpComment accepts Firebase Timestamp time', () {
      final c = SpComment.fromJson({
        '_id': 'cm1',
        'documentId': 'fh1',
        'collection': 'frontHistory',
        'text': 'old comment',
        'time': {'_seconds': 1500000000, '_nanoseconds': 0},
      });
      expect(c.time.millisecondsSinceEpoch, 1500000000000);
    });

    test('SpNote accepts Firebase Timestamp date', () {
      final n = SpNote.fromJson({
        '_id': 'n1',
        'title': 'Old note',
        'note': 'body',
        'member': 'mem1',
        'date': {'_seconds': 1600000000, '_nanoseconds': 0},
      });
      expect(n.date.millisecondsSinceEpoch, 1600000000000);
    });

    test('SpNote date cascades: date → lastOperationTime → createdAt → now', () {
      // date present: wins.
      expect(
        SpNote.fromJson({
          '_id': 'n1',
          'title': 'x',
          'note': 'y',
          'member': 'm1',
          'date': 100,
          'lastOperationTime': 200,
          'createdAt': 300,
        }).date.millisecondsSinceEpoch,
        100,
      );
      // date missing: lastOperationTime wins.
      expect(
        SpNote.fromJson({
          '_id': 'n1',
          'title': 'x',
          'note': 'y',
          'member': 'm1',
          'lastOperationTime': 200,
          'createdAt': 300,
        }).date.millisecondsSinceEpoch,
        200,
      );
      // date + lastOperationTime missing: createdAt wins.
      expect(
        SpNote.fromJson({
          '_id': 'n1',
          'title': 'x',
          'note': 'y',
          'member': 'm1',
          'createdAt': 300,
        }).date.millisecondsSinceEpoch,
        300,
      );
      // All three missing: falls back to the injected clock.
      final fixedNow = DateTime.utc(2024, 5, 1);
      expect(
        SpNote.fromJson(
          {'_id': 'n1', 'title': 'x', 'note': 'y', 'member': 'm1'},
          now: () => fixedNow,
        ).date,
        fixedNow,
      );
    });

    test('SpBoardMessage accepts Firebase Timestamp writtenAt', () {
      final bm = SpBoardMessage.fromJson({
        '_id': 'bm1',
        'writtenBy': 'mem1',
        'writtenFor': 'mem2',
        'message': 'old board post',
        'writtenAt': {'_seconds': 1700000000, '_nanoseconds': 0},
      });
      expect(bm.writtenAt.millisecondsSinceEpoch, 1700000000000);
    });

    test('SpMessage accepts Firebase Timestamp timestamp', () {
      final msg = SpMessage.fromJson({
        '_id': 'msg1',
        'message': 'Hello',
        'writer': 'mem1',
        'writtenAt': {'_seconds': 1684858400, '_nanoseconds': 250000000},
      }, 'ch1');
      expect(msg.timestamp.millisecondsSinceEpoch, 1684858400250);
    });

    test('SpPoll accepts double endTime', () {
      final p = SpPoll.fromJson({
        '_id': 'p1',
        'name': 'Test',
        'endTime': 1684858400123.0,
      });
      expect(p.endDate?.millisecondsSinceEpoch, 1684858400123);
    });

    test('SpChannel accepts int createdAt (modern shape)', () {
      final c = SpChannel.fromJson({
        '_id': 'ch1',
        'name': 'General',
        'createdAt': 1684858400000,
      });
      expect(c.createdAt?.millisecondsSinceEpoch, 1684858400000);
    });

    test('Malformed Map without _seconds returns null / falls back', () {
      final fixedNow = DateTime.utc(2024, 1, 1);
      final fh = SpFrontHistory.fromJson(
        {'_id': 'fh1', 'member': 'mem1', 'startTime': <String, dynamic>{}},
        now: () => fixedNow,
      );
      expect(fh.startTime, fixedNow);

      final msg = SpMessage.fromJson(
        {
          '_id': 'msg1',
          'message': 'x',
          'writer': 'mem1',
          'writtenAt': 1700000000000,
          'updatedAt': <String, dynamic>{},
        },
        'ch1',
      );
      expect(msg.updatedAt, isNull);
    });
  });

  group('Full export parsing', () {
    test('parses empty export gracefully', () {
      final json = jsonEncode({'members': [], 'frontHistory': []});
      final data = SpParser.parse(json);
      expect(data.isEmpty, true);
    });

    test('parses export with all real key names', () {
      final json = jsonEncode({
        'members': [
          {
            '_id': 'mem1',
            'name': 'Kai',
            'pronouns': 'he/him',
            'color': '#4a90d9',
          },
        ],
        'frontStatuses': [
          {'_id': 'cf1', 'name': 'Co-fronting'},
        ],
        'frontHistory': [
          {
            '_id': 'fh1',
            'member': 'mem1',
            'startTime': 1767362442459,
            'endTime': 1767394844459,
            'custom': false,
            'live': false,
          },
        ],
        'chatMessages': [
          {
            '_id': 'msg1',
            'message': 'Hello',
            'channel': 'ch1',
            'writer': 'mem1',
            'writtenAt': 1774242087364,
          },
        ],
        'automatedReminders': [
          {'_id': 'at1', 'name': 'Check', 'delayInHours': 0.5},
        ],
        'repeatedReminders': [
          {
            '_id': 'rt1',
            'name': 'Log',
            'dayInterval': 1,
            'time': {'hour': 9, 'minute': 0},
          },
        ],
        'notes': [
          {
            '_id': 'n1',
            'member': 'mem1',
            'title': 'Test note',
            'note': 'Body',
            'date': 1768435200000,
          },
        ],
        'polls': [
          {
            '_id': 'p1',
            'name': 'Weekend?',
            'options': [
              {'name': 'Hiking'},
            ],
          },
        ],
        'groups': [],
        'channels': [
          {'_id': 'ch1', 'name': 'General'},
        ],
        'customFields': [
          {'_id': 'cf1', 'name': 'Role', 'type': 0},
        ],
      });
      final data = SpParser.parse(json);
      expect(data.members.length, 1);
      expect(data.customFronts.length, 1);
      expect(data.frontHistory.length, 1);
      expect(data.messages.length, 1);
      expect(data.automatedTimers.length, 1);
      expect(data.repeatedTimers.length, 1);
      expect(data.notes.length, 1);
      expect(data.polls.length, 1);
    });
  });

  group('normalizeSpColorHex', () {
    test('null and empty are null', () {
      expect(normalizeSpColorHex(null), isNull);
      expect(normalizeSpColorHex(''), isNull);
      expect(normalizeSpColorHex('   '), isNull);
    });

    test('canonical 6-hex passes through (with or without #)', () {
      expect(normalizeSpColorHex('#ff5733'), 'ff5733');
      expect(normalizeSpColorHex('ff5733'), 'ff5733');
      expect(normalizeSpColorHex('  FF5733  '), 'FF5733');
    });

    test('ARGB 8-hex strips alpha prefix', () {
      expect(normalizeSpColorHex('#80FF5733'), 'FF5733');
      expect(normalizeSpColorHex('80FF5733'), 'FF5733');
      expect(normalizeSpColorHex('#FFAA0000'), 'AA0000');
    });

    test('3-char shorthand expands to 6-char', () {
      expect(normalizeSpColorHex('#abc'), 'aabbcc');
      expect(normalizeSpColorHex('abc'), 'aabbcc');
      expect(normalizeSpColorHex('#F00'), 'FF0000');
    });

    test('rejects non-hex content', () {
      expect(normalizeSpColorHex('#zzzzzz'), isNull);
      expect(normalizeSpColorHex('rgba(0,0,0,1)'), isNull);
      expect(normalizeSpColorHex('#'), isNull);
    });

    test('rejects unsupported lengths', () {
      expect(normalizeSpColorHex('#12345'), isNull);
      expect(normalizeSpColorHex('#1234567'), isNull);
      expect(normalizeSpColorHex('#123456789'), isNull);
    });

    test('preserves case', () {
      expect(normalizeSpColorHex('#aBcDeF'), 'aBcDeF');
    });
  });

  group('rewriteSpMentions', () {
    String? Function(String) resolveTo(String prismId) => (_) => prismId;

    test('empty/null input returns empty/null', () {
      expect(rewriteSpMentions('', (_) => 'p1'), '');
      expect(rewriteSpMentions(null, (_) => 'p1'), '');
      expect(rewriteSpMentionsNullable(null, (_) => 'p1'), isNull);
      expect(rewriteSpMentionsNullable('', (_) => 'p1'), '');
    });

    test('text without tokens returns unchanged', () {
      expect(rewriteSpMentions('hi there', (_) => 'p1'), 'hi there');
      expect(rewriteSpMentions('looks @like a mention', (_) => 'p1'),
          'looks @like a mention');
    });

    test('single resolvable token is rewritten', () {
      final out = rewriteSpMentions(
        'hi <###@sp1###>',
        resolveTo('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'),
      );
      expect(out, 'hi @[aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee]');
    });

    test('unresolvable token is left in place', () {
      final out = rewriteSpMentions('hi <###@unknown###>', (_) => null);
      expect(out, 'hi <###@unknown###>');
    });

    test('mixed resolvable + unresolvable', () {
      final out = rewriteSpMentions(
        'good <###@sp1###> and bad <###@sp2###>',
        (id) => id == 'sp1' ? 'prism-1' : null,
      );
      expect(out, 'good @[prism-1] and bad <###@sp2###>');
    });

    test('multiple resolvable tokens', () {
      final out = rewriteSpMentions(
        '<###@a###> <###@b###> <###@a###>',
        (id) => 'p-$id',
      );
      expect(out, '@[p-a] @[p-b] @[p-a]');
    });

    test('handles short PluralKit-style IDs', () {
      // Pre-v1.50 SP migrated PluralKit-imported members with 5-char `_id`.
      final out = rewriteSpMentions('hi <###@abcde###>', (_) => 'prism-x');
      expect(out, 'hi @[prism-x]');
    });

    test('handles 24-char Mongo ObjectId tokens', () {
      final out = rewriteSpMentions(
        '<###@5f7b9c1d8e3a4b2f1c6d7e8a###>',
        (_) => 'prism-x',
      );
      expect(out, '@[prism-x]');
    });

    test('skips empty token body without rewriting', () {
      // Malformed `<###@###>` (empty body) is left untouched rather than
      // crashing or producing `@[]`.
      final out = rewriteSpMentions('a <###@###> b', (_) => 'p1');
      expect(out, 'a <###@###> b');
    });

    test('does not match unrelated angle-bracket text', () {
      expect(rewriteSpMentions('<#general> hi', (_) => 'p1'),
          '<#general> hi');
      expect(rewriteSpMentions('<@123>', (_) => 'p1'), '<@123>');
      expect(rewriteSpMentions('## @ ##', (_) => 'p1'), '## @ ##');
    });
  });
}
