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
}
