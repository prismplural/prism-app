import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/migration/services/sp_mapper.dart';

/// Helper to build minimal SpExportData for message threading tests.
SpExportData _makeData({
  List<SpMember> members = const [],
  List<SpChannel> channels = const [],
  List<SpMessage> messages = const [],
}) {
  return SpExportData(
    members: members,
    customFronts: const [],
    frontHistory: const [],
    groups: const [],
    channels: channels,
    messages: messages,
    polls: const [],
  );
}

const _channel = SpChannel(id: 'ch1', name: 'General');
const _member = SpMember(id: 'sp-a', name: 'Alice');

void main() {
  // ---------------------------------------------------------------------------
  // SpMessage.fromJson — parser tests
  // ---------------------------------------------------------------------------
  group('SpMessage.fromJson — replyTo and updatedAt parsing', () {
    test('parses replyTo field', () {
      final msg = SpMessage.fromJson({
        '_id': 'msg2',
        'channel': 'ch1',
        'writer': 'sp-a',
        'message': 'Reply here',
        'writtenAt': 1700000000000,
        'replyTo': 'msg1',
      }, 'ch1');

      expect(msg.replyTo, 'msg1');
    });

    test('empty string replyTo is treated as null', () {
      final msg = SpMessage.fromJson({
        '_id': 'msg2',
        'channel': 'ch1',
        'writer': 'sp-a',
        'message': 'No reply',
        'writtenAt': 1700000000000,
        'replyTo': '',
      }, 'ch1');

      expect(msg.replyTo, isNull);
    });

    test('absent replyTo is null', () {
      final msg = SpMessage.fromJson({
        '_id': 'msg1',
        'channel': 'ch1',
        'writer': 'sp-a',
        'message': 'First message',
        'writtenAt': 1700000000000,
      }, 'ch1');

      expect(msg.replyTo, isNull);
    });

    test('parses updatedAt as int epoch ms', () {
      const base = 1700000000000;
      const edit = base + 60000; // 1 minute later
      final msg = SpMessage.fromJson({
        '_id': 'msg1',
        'channel': 'ch1',
        'writer': 'sp-a',
        'message': 'Edited message',
        'writtenAt': base,
        'updatedAt': edit,
      }, 'ch1');

      expect(msg.updatedAt, DateTime.fromMillisecondsSinceEpoch(edit));
    });

    test('absent updatedAt is null', () {
      final msg = SpMessage.fromJson({
        '_id': 'msg1',
        'channel': 'ch1',
        'writer': 'sp-a',
        'message': 'Unedited',
        'writtenAt': 1700000000000,
      }, 'ch1');

      expect(msg.updatedAt, isNull);
    });

    test('falls back to lastUpdated when updatedAt absent', () {
      const base = 1700000000000;
      const edit = base + 60000;
      final msg = SpMessage.fromJson({
        '_id': 'msg1',
        'channel': 'ch1',
        'writer': 'sp-a',
        'message': 'Edited',
        'writtenAt': base,
        'lastUpdated': edit,
      }, 'ch1');

      expect(msg.updatedAt, DateTime.fromMillisecondsSinceEpoch(edit));
    });
  });

  // ---------------------------------------------------------------------------
  // SpMapper._mapMessages — threading and editedAt tests
  // ---------------------------------------------------------------------------
  group('SpMapper — message reply threading (two-pass)', () {
    test('replyToId is resolved when parent message is present', () {
      final data = _makeData(
        members: [_member],
        channels: [_channel],
        messages: [
          SpMessage(
            id: 'sp-msg1',
            channelId: 'ch1',
            senderId: 'sp-a',
            content: 'Original message',
            timestamp: DateTime(2024, 1, 1, 10),
          ),
          SpMessage(
            id: 'sp-msg2',
            channelId: 'ch1',
            senderId: 'sp-a',
            content: 'Reply to original',
            timestamp: DateTime(2024, 1, 1, 10, 1),
            replyTo: 'sp-msg1',
          ),
        ],
      );

      final result = SpMapper().mapAll(data);
      expect(result.messages, hasLength(2));

      final original = result.messages.firstWhere(
        (m) => m.content == 'Original message',
      );
      final reply = result.messages.firstWhere(
        (m) => m.content == 'Reply to original',
      );

      expect(reply.replyToId, original.id);
      expect(original.replyToId, isNull);
    });

    test('replyToId is null when parent message was not imported', () {
      final data = _makeData(
        members: [_member],
        channels: [_channel],
        messages: [
          SpMessage(
            id: 'sp-msg2',
            channelId: 'ch1',
            senderId: 'sp-a',
            content: 'Orphan reply',
            timestamp: DateTime(2024, 1, 1),
            // References a message not in the export.
            replyTo: 'nonexistent-msg',
          ),
        ],
      );

      final result = SpMapper().mapAll(data);
      expect(result.messages, hasLength(1));
      expect(result.messages.first.replyToId, isNull);
    });

    test('chain of three replies preserves full threading', () {
      final data = _makeData(
        members: [_member],
        channels: [_channel],
        messages: [
          SpMessage(
            id: 'sp-a',
            channelId: 'ch1',
            senderId: 'sp-a',
            content: 'Root',
            timestamp: DateTime(2024, 1, 1, 10),
          ),
          SpMessage(
            id: 'sp-b',
            channelId: 'ch1',
            senderId: 'sp-a',
            content: 'Child of root',
            timestamp: DateTime(2024, 1, 1, 10, 1),
            replyTo: 'sp-a',
          ),
          SpMessage(
            id: 'sp-c',
            channelId: 'ch1',
            senderId: 'sp-a',
            content: 'Grandchild',
            timestamp: DateTime(2024, 1, 1, 10, 2),
            replyTo: 'sp-b',
          ),
        ],
      );

      final result = SpMapper().mapAll(data);
      expect(result.messages, hasLength(3));

      final root = result.messages.firstWhere((m) => m.content == 'Root');
      final child = result.messages.firstWhere((m) => m.content == 'Child of root');
      final grandchild = result.messages.firstWhere((m) => m.content == 'Grandchild');

      expect(root.replyToId, isNull);
      expect(child.replyToId, root.id);
      expect(grandchild.replyToId, child.id);
    });

    test('messages with no replyTo still import cleanly', () {
      final data = _makeData(
        members: [_member],
        channels: [_channel],
        messages: [
          SpMessage(
            id: 'sp-msg1',
            channelId: 'ch1',
            senderId: 'sp-a',
            content: 'Hello',
            timestamp: DateTime(2024, 1, 1),
          ),
        ],
      );

      final result = SpMapper().mapAll(data);
      expect(result.messages, hasLength(1));
      expect(result.messages.first.replyToId, isNull);
      expect(result.messages.first.editedAt, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // SpMapper._mapMessages — editedAt tests
  // ---------------------------------------------------------------------------
  group('SpMapper — message editedAt mapping', () {
    test('editedAt is set when updatedAt differs by more than 1 second', () {
      final base = DateTime(2024, 1, 1, 10, 0, 0);
      final edit = base.add(const Duration(minutes: 5));

      final data = _makeData(
        members: [_member],
        channels: [_channel],
        messages: [
          SpMessage(
            id: 'sp-msg1',
            channelId: 'ch1',
            senderId: 'sp-a',
            content: 'Edited message',
            timestamp: base,
            updatedAt: edit,
          ),
        ],
      );

      final result = SpMapper().mapAll(data);
      expect(result.messages.first.editedAt, edit);
    });

    test('editedAt is null when updatedAt equals timestamp (within 1 second)', () {
      final ts = DateTime(2024, 1, 1, 10, 0, 0);

      final data = _makeData(
        members: [_member],
        channels: [_channel],
        messages: [
          SpMessage(
            id: 'sp-msg1',
            channelId: 'ch1',
            senderId: 'sp-a',
            content: 'Not edited',
            timestamp: ts,
            // Same time — SP sometimes sets updatedAt = writtenAt on creation.
            updatedAt: ts,
          ),
        ],
      );

      final result = SpMapper().mapAll(data);
      expect(result.messages.first.editedAt, isNull);
    });

    test('editedAt is null when updatedAt is absent', () {
      final data = _makeData(
        members: [_member],
        channels: [_channel],
        messages: [
          SpMessage(
            id: 'sp-msg1',
            channelId: 'ch1',
            senderId: 'sp-a',
            content: 'No edit',
            timestamp: DateTime(2024, 1, 1),
          ),
        ],
      );

      final result = SpMapper().mapAll(data);
      expect(result.messages.first.editedAt, isNull);
    });
  });
}
