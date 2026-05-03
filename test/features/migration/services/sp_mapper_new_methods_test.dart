import 'package:flutter_test/flutter_test.dart';
import 'package:prism_plurality/core/constants/fronting_namespaces.dart';
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
          SpNote(id: 'n1', title: '', body: '', date: DateTime(2024, 1, 1)),
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
    test(
      'comment on frontHistory collection gets mapped with resolved session ID',
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
        expect(
          result.frontComments.first.sessionId,
          mapper.sessionIdMap['fh1'],
        );
        expect(result.frontComments.first.id, deriveSpFrontCommentId('c1'));
        expect(result.frontComments.first.timestamp, DateTime(2024, 1, 1, 12));
        expect(result.warnings, isEmpty);
      },
    );

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

    test(
      'values extracted from member info maps with correct field+member resolution',
      () {
        final data = _makeExportData(
          members: [
            const SpMember(id: 'sp-a', name: 'Alice', info: {'cf1': 'Blue'}),
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
        expect(
          result.customFieldValues.first.customFieldId,
          result.customFields.first.id,
        );
        // The memberId should match the Prism UUID for sp-a
        expect(
          result.customFieldValues.first.memberId,
          result.members.first.id,
        );
      },
    );
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
          const SpGroup(id: 'g1', name: 'Team', memberIds: ['sp-a', 'sp-b']),
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
      expect(result.warnings.any((w) => w.contains('nonexistent')), isTrue);
    });
  });

  group('Board messages mapping', () {
    test(
      'board messages produce MemberBoardPost rows, not DM conversations',
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

        // No synthetic DM conversations are created for board messages.
        final boardConvs = result.conversations
            .where((c) => c.emoji == '\u{1F4DD}')
            .toList();
        expect(boardConvs, isEmpty);

        // Two first-class MemberBoardPost rows are produced instead.
        expect(result.boardPosts, hasLength(2));

        // Each post is private, has the correct author and recipient.
        final prismIdA = result.members.firstWhere((m) => m.name == 'Alice').id;
        final prismIdB = result.members.firstWhere((m) => m.name == 'Bob').id;

        for (final post in result.boardPosts) {
          expect(post.audience, 'private');
          expect(post.authorId, prismIdA);
          expect(post.targetMemberId, prismIdB);
        }

        expect(result.warnings, isEmpty);
      },
    );

    test(
      'A→B and B→A board messages each produce separate MemberBoardPost rows',
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

        // No synthetic DM conversations.
        expect(
          result.conversations.where((c) => c.emoji == '\u{1F4DD}'),
          isEmpty,
        );

        // Two independent posts — directionality preserved.
        expect(result.boardPosts, hasLength(2));

        final prismIdA = result.members.firstWhere((m) => m.name == 'Alice').id;
        final prismIdB = result.members.firstWhere((m) => m.name == 'Bob').id;

        final postAtob = result.boardPosts.firstWhere(
          (p) => p.authorId == prismIdA,
        );
        expect(postAtob.targetMemberId, prismIdB);

        final postBtoa = result.boardPosts.firstWhere(
          (p) => p.authorId == prismIdB,
        );
        expect(postBtoa.targetMemberId, prismIdA);
      },
    );

    test(
      'message with unknown recipient (writtenFor not in members map) is skipped with warning',
      () {
        final data = _makeExportData(
          members: [_memberA],
          boardMessages: [
            SpBoardMessage(
              id: 'bm1',
              writtenBy: 'sp-a',
              writtenFor: 'unknown-y',
              message: 'Orphan message',
              writtenAt: DateTime(2024, 1, 1),
            ),
          ],
        );

        final mapper = SpMapper();
        final result = mapper.mapAll(data);

        // No board posts should be created for unresolved recipients.
        expect(result.boardPosts, isEmpty);

        expect(result.warnings, isNotEmpty);
        expect(result.warnings.any((w) => w.contains('bm1')), isTrue);
      },
    );

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

      expect(result.boardPosts, isEmpty);
      // Empty board messages do not create DM conversations either.
      expect(
        result.conversations.where((c) => c.emoji == '\u{1F4DD}'),
        isEmpty,
      );
    });

    test('title is stored on the MemberBoardPost, not prepended to body', () {
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

      expect(result.boardPosts, hasLength(1));
      final post = result.boardPosts.first;
      // Title is its own field on MemberBoardPost.
      expect(post.title, 'Important');
      // Body contains only the message text, no bold-prefix prepending.
      expect(post.body, 'Read this please');
      expect(post.audience, 'private');
    });

    test(
      'SP read:true propagates to boardLastReadAtUpdates for the recipient',
      () {
        final data = _makeExportData(
          members: [_memberA, _memberB],
          boardMessages: [
            SpBoardMessage(
              id: 'bm1',
              writtenBy: 'sp-a',
              writtenFor: 'sp-b',
              message: 'Already read message',
              writtenAt: DateTime(2024, 3, 10, 12),
              read: true,
            ),
            SpBoardMessage(
              id: 'bm2',
              writtenBy: 'sp-a',
              writtenFor: 'sp-b',
              message: 'Unread message',
              writtenAt: DateTime(2024, 3, 10, 15),
              read: false,
            ),
          ],
        );

        final mapper = SpMapper();
        final result = mapper.mapAll(data);

        expect(result.boardPosts, hasLength(2));

        final prismIdB = result.members.firstWhere((m) => m.name == 'Bob').id;

        // boardLastReadAtUpdates should record the high-water-mark for Bob
        // from the read=true message only.
        expect(result.boardLastReadAtUpdates.containsKey(prismIdB), isTrue);
        expect(
          result.boardLastReadAtUpdates[prismIdB],
          DateTime(2024, 3, 10, 12),
        );
      },
    );

    test('writtenFor:null produces an import warning and no board post', () {
      final data = _makeExportData(
        members: [_memberA, _memberB],
        boardMessages: [
          SpBoardMessage(
            id: 'bm-null-for',
            writtenBy: 'sp-a',
            writtenFor: null,
            message: 'No recipient set',
            writtenAt: DateTime(2024, 1, 1),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      // Null writtenFor is not silently re-targeted — it is skipped.
      expect(result.boardPosts, isEmpty);

      expect(result.warnings, isNotEmpty);
      expect(result.warnings.any((w) => w.contains('bm-null-for')), isTrue);
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
          SpChannel(id: 'ch-pair', name: 'Pair', memberIds: ['sp-a', 'sp-b']),
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
