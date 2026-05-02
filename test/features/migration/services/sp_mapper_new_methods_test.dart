import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/features/migration/services/sp_parser.dart';
import 'package:prism_plurality/features/migration/services/sp_mapper.dart';
import 'package:prism_plurality/domain/models/custom_field.dart' as domain;

/// Helper to create minimal SpExportData with sensible defaults.
SpExportData _makeExportData({
  List<SpMember> members = const [],
  List<SpCustomFront> customFronts = const [],
  List<SpFrontHistory> frontHistory = const [],
  List<SpGroup> groups = const [],
  List<SpChannel> channels = const [],
  List<SpMessage> messages = const [],
  List<SpPoll> polls = const [],
  List<SpNote> notes = const [],
  List<SpComment> comments = const [],
  List<SpCustomFieldDef> customFields = const [],
  List<SpBoardMessage> boardMessages = const [],
}) {
  return SpExportData(
    members: members,
    customFronts: customFronts,
    frontHistory: frontHistory,
    groups: groups,
    channels: channels,
    messages: messages,
    polls: polls,
    notes: notes,
    comments: comments,
    customFields: customFields,
    boardMessages: boardMessages,
  );
}

/// Two standard test members used across multiple test groups.
const _memberA = SpMember(id: 'sp-a', name: 'Alice');
const _memberB = SpMember(id: 'sp-b', name: 'Bob');

void main() {
  group('Notes mapping', () {
    test('note with valid memberId gets resolved', () {
      final data = _makeExportData(
        members: [_memberA],
        notes: [
          SpNote(
            id: 'n1',
            title: 'My Note',
            body: 'Content',
            memberId: 'sp-a',
            date: DateTime(2024, 1, 1),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.notes, hasLength(1));
      expect(result.notes.first.memberId, isNotNull);
      // memberId should be the Prism UUID assigned to member 'sp-a'
      expect(result.notes.first.memberId, result.members.first.id);
      expect(result.warnings, isEmpty);
    });

    test('note with unknown memberId emits warning, note still created', () {
      final data = _makeExportData(
        members: [_memberA],
        notes: [
          SpNote(
            id: 'n1',
            title: 'Orphan Note',
            body: 'Content',
            memberId: 'nonexistent-member',
            date: DateTime(2024, 1, 1),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.notes, hasLength(1));
      expect(result.notes.first.memberId, isNull);
      expect(result.warnings, isNotEmpty);
      expect(
        result.warnings.any((w) => w.contains('nonexistent-member')),
        isTrue,
      );
    });

    test('note with empty body AND empty title is skipped', () {
      final data = _makeExportData(
        members: [],
        notes: [
          SpNote(
            id: 'n1',
            title: '',
            body: '',
            date: DateTime(2024, 1, 1),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.notes, isEmpty);
    });

    test('color hex gets "#" prefix added if missing', () {
      final data = _makeExportData(
        notes: [
          SpNote(
            id: 'n1',
            title: 'Colored Note',
            body: 'Content',
            color: 'FF5733',
            date: DateTime(2024, 1, 1),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.notes.first.colorHex, '#FF5733');
    });

    test('bare "#" color becomes null', () {
      final data = _makeExportData(
        notes: [
          SpNote(
            id: 'n1',
            title: 'Note',
            body: 'Content',
            color: '#',
            date: DateTime(2024, 1, 1),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.notes.first.colorHex, isNull);
    });
  });

  group('Front comments mapping', () {
    test('comment on frontHistory collection gets mapped with resolved session ID',
        () {
      final frontEntry = SpFrontHistory(
        id: 'fh1',
        memberId: 'sp-a',
        startTime: DateTime(2024, 1, 1),
      );

      final data = _makeExportData(
        members: [_memberA],
        frontHistory: [frontEntry],
        comments: [
          SpComment(
            id: 'c1',
            documentId: 'fh1',
            collection: 'frontHistory',
            text: 'A comment on this session',
            time: DateTime(2024, 1, 1, 12),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.frontComments, hasLength(1));
      expect(result.frontComments.first.body, 'A comment on this session');
      // Comments now anchor to targetTime (the SP comment's own timestamp)
      // rather than a sessionId FK.  Verify the comment's targetTime was set.
      expect(result.frontComments.first.targetTime, DateTime(2024, 1, 1, 12));
      expect(result.warnings, isEmpty);
    });

    test('comment on non-frontHistory collection is skipped', () {
      final data = _makeExportData(
        members: [_memberA],
        frontHistory: [
          SpFrontHistory(
            id: 'fh1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1),
          ),
        ],
        comments: [
          SpComment(
            id: 'c1',
            documentId: 'fh1',
            collection: 'members',
            text: 'This should be skipped',
            time: DateTime(2024, 1, 1),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.frontComments, isEmpty);
    });

    test('comment with unknown documentId emits warning and is skipped', () {
      final data = _makeExportData(
        members: [_memberA],
        frontHistory: [
          SpFrontHistory(
            id: 'fh1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1),
          ),
        ],
        comments: [
          SpComment(
            id: 'c1',
            documentId: 'nonexistent-session',
            collection: 'frontHistory',
            text: 'Orphan comment',
            time: DateTime(2024, 1, 1),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.frontComments, isEmpty);
      expect(result.warnings, isNotEmpty);
      expect(
        result.warnings.any((w) => w.contains('nonexistent-session')),
        isTrue,
      );
    });

    test('empty text comment is skipped', () {
      final data = _makeExportData(
        members: [_memberA],
        frontHistory: [
          SpFrontHistory(
            id: 'fh1',
            memberId: 'sp-a',
            startTime: DateTime(2024, 1, 1),
          ),
        ],
        comments: [
          SpComment(
            id: 'c1',
            documentId: 'fh1',
            collection: 'frontHistory',
            text: '',
            time: DateTime(2024, 1, 1),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.frontComments, isEmpty);
    });
  });

  group('Custom fields mapping', () {
    test('field type "color" maps to CustomFieldType.color', () {
      final data = _makeExportData(
        customFields: [
          const SpCustomFieldDef(id: 'cf1', name: 'Fav Color', type: 1),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.customFields, hasLength(1));
      expect(result.customFields.first.fieldType, domain.CustomFieldType.color);
    });

    test('field type "date" maps to CustomFieldType.date', () {
      final data = _makeExportData(
        customFields: [
          const SpCustomFieldDef(id: 'cf1', name: 'Birthday', type: 2),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.customFields.first.fieldType, domain.CustomFieldType.date);
    });

    test('unknown type maps to CustomFieldType.text', () {
      final data = _makeExportData(
        customFields: [
          const SpCustomFieldDef(id: 'cf1', name: 'Other', type: 99),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.customFields.first.fieldType, domain.CustomFieldType.text);
    });

    test('values extracted from member info maps with correct field+member resolution',
        () {
      final data = _makeExportData(
        members: [
          const SpMember(
            id: 'sp-a',
            name: 'Alice',
            info: {'cf1': 'Blue'},
          ),
        ],
        customFields: [
          const SpCustomFieldDef(id: 'cf1', name: 'Fav Color', type: 1),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.customFieldValues, hasLength(1));
      expect(result.customFieldValues.first.value, 'Blue');
      // The customFieldId should match the Prism UUID for cf1
      expect(result.customFieldValues.first.customFieldId,
          result.customFields.first.id);
      // The memberId should match the Prism UUID for sp-a
      expect(
          result.customFieldValues.first.memberId, result.members.first.id);
    });
  });

  group('Groups mapping', () {
    test('groups mapped with color normalization', () {
      final data = _makeExportData(
        groups: [
          const SpGroup(id: 'g1', name: 'Group A', color: 'FF0000'),
          const SpGroup(id: 'g2', name: 'Group B', color: '#00FF00'),
          const SpGroup(id: 'g3', name: 'Group C', color: '#'),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.groups, hasLength(3));
      expect(result.groups[0].colorHex, '#FF0000');
      expect(result.groups[1].colorHex, '#00FF00');
      expect(result.groups[2].colorHex, isNull);
    });

    test('group memberships resolved via member ID map', () {
      final data = _makeExportData(
        members: [_memberA, _memberB],
        groups: [
          const SpGroup(
              id: 'g1', name: 'Team', memberIds: ['sp-a', 'sp-b']),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.groupMemberships, hasLength(2));
      // Group ID should be the Prism UUID for g1
      final groupId = result.groups.first.id;
      expect(result.groupMemberships[0].key, groupId);
      expect(result.groupMemberships[1].key, groupId);
      // Member IDs should be resolved Prism UUIDs
      final memberIds = result.members.map((m) => m.id).toSet();
      expect(memberIds.contains(result.groupMemberships[0].value), isTrue);
      expect(memberIds.contains(result.groupMemberships[1].value), isTrue);
    });

    test('unknown member in group emits warning', () {
      final data = _makeExportData(
        members: [_memberA],
        groups: [
          const SpGroup(
            id: 'g1',
            name: 'Team',
            memberIds: ['sp-a', 'nonexistent'],
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      // Only sp-a should be resolved
      expect(result.groupMemberships, hasLength(1));
      expect(result.warnings, isNotEmpty);
      expect(
        result.warnings.any((w) => w.contains('nonexistent')),
        isTrue,
      );
    });
  });

  group('Board messages mapping', () {
    test('messages grouped by (writtenBy, writtenFor) pair into DM conversations',
        () {
      final data = _makeExportData(
        members: [_memberA, _memberB],
        boardMessages: [
          SpBoardMessage(
            id: 'bm1',
            writtenBy: 'sp-a',
            writtenFor: 'sp-b',
            message: 'Hello Bob!',
            writtenAt: DateTime(2024, 1, 1),
          ),
          SpBoardMessage(
            id: 'bm2',
            writtenBy: 'sp-a',
            writtenFor: 'sp-b',
            message: 'How are you?',
            writtenAt: DateTime(2024, 1, 2),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      // Both messages in same pair should create one conversation
      final boardConvs = result.conversations
          .where((c) => c.emoji == '\u{1F4DD}')
          .toList();
      expect(boardConvs, hasLength(1));

      // Two messages in that conversation
      final convId = boardConvs.first.id;
      final boardMsgs =
          result.messages.where((m) => m.conversationId == convId).toList();
      expect(boardMsgs, hasLength(2));
    });

    test('order-independent pair key (A->B and B->A go to same conversation)',
        () {
      final data = _makeExportData(
        members: [_memberA, _memberB],
        boardMessages: [
          SpBoardMessage(
            id: 'bm1',
            writtenBy: 'sp-a',
            writtenFor: 'sp-b',
            message: 'From A to B',
            writtenAt: DateTime(2024, 1, 1),
          ),
          SpBoardMessage(
            id: 'bm2',
            writtenBy: 'sp-b',
            writtenFor: 'sp-a',
            message: 'From B to A',
            writtenAt: DateTime(2024, 1, 2),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      // Should still be only one DM conversation
      final boardConvs = result.conversations
          .where((c) => c.emoji == '\u{1F4DD}')
          .toList();
      expect(boardConvs, hasLength(1));

      final convId = boardConvs.first.id;
      final boardMsgs =
          result.messages.where((m) => m.conversationId == convId).toList();
      expect(boardMsgs, hasLength(2));
    });

    test('message with both unknown sender+recipient is skipped with warning',
        () {
      final data = _makeExportData(
        members: [_memberA],
        boardMessages: [
          SpBoardMessage(
            id: 'bm1',
            writtenBy: 'unknown-x',
            writtenFor: 'unknown-y',
            message: 'Orphan message',
            writtenAt: DateTime(2024, 1, 1),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      // No DM conversations should be created
      final boardConvs = result.conversations
          .where((c) => c.emoji == '\u{1F4DD}')
          .toList();
      expect(boardConvs, isEmpty);

      expect(result.warnings, isNotEmpty);
      expect(
        result.warnings.any((w) => w.contains('bm1')),
        isTrue,
      );
    });

    test('empty message is skipped', () {
      final data = _makeExportData(
        members: [_memberA, _memberB],
        boardMessages: [
          SpBoardMessage(
            id: 'bm1',
            writtenBy: 'sp-a',
            writtenFor: 'sp-b',
            message: '',
            writtenAt: DateTime(2024, 1, 1),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      final boardConvs = result.conversations
          .where((c) => c.emoji == '\u{1F4DD}')
          .toList();
      expect(boardConvs, isEmpty);
    });

    test('title prepended to content with markdown bold', () {
      final data = _makeExportData(
        members: [_memberA, _memberB],
        boardMessages: [
          SpBoardMessage(
            id: 'bm1',
            writtenBy: 'sp-a',
            writtenFor: 'sp-b',
            title: 'Important',
            message: 'Read this please',
            writtenAt: DateTime(2024, 1, 1),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      final boardConvs = result.conversations
          .where((c) => c.emoji == '\u{1F4DD}')
          .toList();
      expect(boardConvs, hasLength(1));

      final convId = boardConvs.first.id;
      final boardMsgs =
          result.messages.where((m) => m.conversationId == convId).toList();
      expect(boardMsgs, hasLength(1));
      expect(boardMsgs.first.content, '**Important**\nRead this please');
    });
  });

  group('Channel mapping — DM classification', () {
    test('SP channel with no members is not a DM', () {
      // Real SP exports often omit the `members` field entirely on channels
      // (the channel is server-wide). Marking these as DMs combined with the
      // DM-privacy filter would hide them from everyone.
      final data = _makeExportData(
        members: [_memberA, _memberB],
        channels: const [SpChannel(id: 'ch-general', name: 'General')],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.conversations, hasLength(1));
      expect(result.conversations.first.isDirectMessage, isFalse);
      expect(result.conversations.first.participantIds, isEmpty);
    });

    test('SP channel with two members is still not a DM', () {
      // SP channels are group chats by SP's data model regardless of member
      // count. A 2-member channel is still a channel, not a DM.
      final data = _makeExportData(
        members: [_memberA, _memberB],
        channels: const [
          SpChannel(
            id: 'ch-pair',
            name: 'Pair',
            memberIds: ['sp-a', 'sp-b'],
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.conversations, hasLength(1));
      expect(result.conversations.first.isDirectMessage, isFalse);
      expect(result.conversations.first.participantIds, hasLength(2));
    });
  });
}
