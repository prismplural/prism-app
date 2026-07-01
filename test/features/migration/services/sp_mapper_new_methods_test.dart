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

    test(
      'mixed comment collections only import frontHistory-scoped comments',
      () {
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
              id: 'c-front',
              documentId: 'fh1',
              collection: 'frontHistory',
              text: 'Keep me',
              time: DateTime(2024, 1, 1, 12),
            ),
            SpComment(
              id: 'c-member',
              documentId: 'sp-a',
              collection: 'members',
              text: 'Ignore me',
              time: DateTime(2024, 1, 1, 13),
            ),
            SpComment(
              id: 'c-orphan',
              documentId: 'missing-fh',
              collection: 'frontHistory',
              text: 'Warn and skip me',
              time: DateTime(2024, 1, 1, 14),
            ),
          ],
        );

        final mapper = SpMapper();
        final result = mapper.mapAll(data);

        expect(result.frontComments, hasLength(1));
        expect(result.frontComments.single.body, 'Keep me');
        expect(result.warnings.any((w) => w.contains('missing-fh')), isTrue);
        expect(result.warnings.any((w) => w.contains('c-member')), isFalse);
      },
    );
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

    test('markdown text fields map to CustomFieldType.longText', () {
      final data = _makeExportData(
        customFields: [
          const SpCustomFieldDef(
            id: 'cf1',
            name: 'Backstory',
            type: 0,
            supportMarkdown: true,
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(
        result.customFields.first.fieldType,
        domain.CustomFieldType.longText,
      );
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

    test(
      'member info values are stringified and empty or unknown entries are dropped',
      () {
        final data = _makeExportData(
          members: [
            const SpMember(
              id: 'sp-a',
              name: 'Alice',
              info: {
                'cf-text': 'Blue',
                'cf-bool': true,
                'cf-list': ['alpha', 'beta'],
                'cf-num': 7,
                'cf-empty': '',
                'cf-null': null,
                'cf-unknown': 'skip',
              },
            ),
          ],
          customFields: [
            const SpCustomFieldDef(id: 'cf-text', name: 'Text', type: 0),
            const SpCustomFieldDef(id: 'cf-bool', name: 'Bool', type: 0),
            const SpCustomFieldDef(id: 'cf-list', name: 'List', type: 0),
            const SpCustomFieldDef(id: 'cf-num', name: 'Num', type: 0),
            const SpCustomFieldDef(id: 'cf-empty', name: 'Empty', type: 0),
            const SpCustomFieldDef(id: 'cf-null', name: 'Null', type: 0),
          ],
        );

        final mapper = SpMapper();
        final result = mapper.mapAll(data);

        expect(result.customFieldValues, hasLength(4));
        expect(result.customFieldValues.map((value) => value.value).toSet(), {
          'Blue',
          'true',
          '[alpha, beta]',
          '7',
        });
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

    test('duplicate group memberships are mapped once', () {
      final data = _makeExportData(
        members: [_memberA],
        groups: [
          const SpGroup(id: 'g1', name: 'Team', memberIds: ['sp-a', 'sp-a']),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.groupMemberships, hasLength(1));
    });

    test('same member in different groups keeps both memberships', () {
      final data = _makeExportData(
        members: [_memberA],
        groups: [
          const SpGroup(id: 'g1', name: 'Team A', memberIds: ['sp-a']),
          const SpGroup(id: 'g2', name: 'Team B', memberIds: ['sp-a']),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.groupMemberships, hasLength(2));
      expect(
        result.groupMemberships.map((membership) => membership.key).toSet(),
        hasLength(2),
      );
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

    test('legacy _board chat messages do not synthesize chat imports', () {
      final data = _makeExportData(
        members: [_memberA, _memberB],
        messages: [
          SpMessage(
            id: 'legacy-board-msg',
            channelId: '_board',
            senderId: 'sp-a',
            content: 'Legacy board payload',
            timestamp: DateTime(2024, 1, 1),
          ),
        ],
        boardMessages: [
          SpBoardMessage(
            id: 'bm1',
            writtenBy: 'sp-a',
            writtenFor: 'sp-b',
            message: 'Real board payload',
            writtenAt: DateTime(2024, 1, 2),
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.conversations, isEmpty);
      expect(result.messages, isEmpty);
      expect(result.boardPosts, hasLength(1));
      expect(result.boardPosts.first.body, 'Real board payload');
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

  group('Poll mapping', () {
    test('standard polls synthesize default options and preserve votes', () {
      final data = _makeExportData(
        members: [_memberA],
        polls: [
          const SpPoll(
            id: 'p1',
            question: 'Test poll',
            isCustom: false,
            allowAbstain: true,
            allowVeto: true,
            votes: [SpPollVote(memberId: 'sp-a', optionName: 'yes')],
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.polls, hasLength(1));
      expect(result.polls.first.options.map((o) => o.text).toList(), [
        'Yes',
        'No',
        'Abstain',
        'Veto',
      ]);
      final yesOption = result.polls.first.options.firstWhere(
        (o) => o.text == 'Yes',
      );
      expect(yesOption.votes, hasLength(1));
      expect(yesOption.votes.first.memberId, result.members.first.id);
    });

    test(
      'multi-select custom polls preserve allowsMultipleVotes and per-option votes',
      () {
        final data = _makeExportData(
          members: [_memberA, _memberB],
          polls: [
            const SpPoll(
              id: 'p1',
              question: 'Pick multiple',
              isCustom: true,
              allowMultiple: true,
              options: [
                SpPollOption(name: 'Alpha', color: '#AA0000'),
                SpPollOption(name: 'Beta', color: '#00BB00'),
              ],
              votes: [
                SpPollVote(
                  memberId: 'sp-a',
                  optionName: 'Alpha',
                  comment: 'first pick',
                ),
                SpPollVote(memberId: 'sp-a', optionName: 'Beta'),
                SpPollVote(memberId: 'sp-b', optionName: 'Beta'),
              ],
            ),
          ],
        );

        final mapper = SpMapper();
        final result = mapper.mapAll(data);

        expect(result.polls, hasLength(1));
        final poll = result.polls.single;
        expect(poll.allowsMultipleVotes, isTrue);

        final alpha = poll.options.firstWhere(
          (option) => option.text == 'Alpha',
        );
        final beta = poll.options.firstWhere((option) => option.text == 'Beta');

        expect(alpha.votes, hasLength(1));
        expect(alpha.votes.single.responseText, 'first pick');
        expect(beta.votes, hasLength(2));
      },
    );
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
      expect(result.conversations.first.includesAllMembers, isTrue);
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
      expect(result.conversations.first.includesAllMembers, isFalse);
    });

    test('SP channel with no resolved members includes everyone', () {
      final data = _makeExportData(
        members: [_memberA],
        channels: const [
          SpChannel(
            id: 'ch-orphaned',
            name: 'Orphaned',
            memberIds: ['missing-sp-member'],
          ),
        ],
      );

      final mapper = SpMapper();
      final result = mapper.mapAll(data);

      expect(result.conversations, hasLength(1));
      expect(result.conversations.first.participantIds, isEmpty);
      expect(result.conversations.first.includesAllMembers, isTrue);
    });
  });

  group('Front history corruption skips', () {
    test('skips entries with missing startTime and adds a warning', () {
      final data = _makeExportData(
        members: [_memberA],
        frontHistory: [
          SpFrontHistory.fromJson({'_id': 'fh1', 'member': 'sp-a'}),
        ],
      );
      final result = SpMapper().mapAll(data);
      expect(result.sessions, isEmpty);
      expect(
        result.warnings.any((w) => w.contains('no startTime')),
        isTrue,
      );
    });

    test('keeps live=false with no endTime as an open-ended session', () {
      final data = _makeExportData(
        members: [_memberA],
        frontHistory: [
          SpFrontHistory.fromJson({
            '_id': 'fh1',
            'member': 'sp-a',
            'startTime': 1000,
          }),
        ],
      );
      final result = SpMapper().mapAll(data);
      expect(result.sessions, hasLength(1));
      expect(result.sessions.single.endTime, isNull);
    });

    test('keeps live=true with no endTime (active front)', () {
      final data = _makeExportData(
        members: [_memberA],
        frontHistory: [
          SpFrontHistory.fromJson({
            '_id': 'fh1',
            'member': 'sp-a',
            'startTime': 1000,
            'live': true,
          }),
        ],
      );
      final result = SpMapper().mapAll(data);
      expect(result.sessions, hasLength(1));
      expect(result.sessions.single.endTime, isNull);
    });

    test('keeps live=false with explicit endTime (ended front)', () {
      final data = _makeExportData(
        members: [_memberA],
        frontHistory: [
          SpFrontHistory.fromJson({
            '_id': 'fh1',
            'member': 'sp-a',
            'startTime': 1000,
            'endTime': 2000,
          }),
        ],
      );
      final result = SpMapper().mapAll(data);
      expect(result.sessions, hasLength(1));
      expect(
        result.sessions.single.endTime?.millisecondsSinceEpoch,
        2000,
      );
    });

    test('aggregates multiple missing-startTime drops into one warning', () {
      final data = _makeExportData(
        members: [_memberA],
        frontHistory: [
          SpFrontHistory.fromJson({'_id': 'fh1', 'member': 'sp-a'}),
          SpFrontHistory.fromJson({'_id': 'fh2', 'member': 'sp-a'}),
        ],
      );
      final result = SpMapper().mapAll(data);
      expect(result.sessions, isEmpty);
      final missingWarnings = result.warnings
          .where((w) => w.contains('no startTime'))
          .toList();
      expect(missingWarnings, hasLength(1));
      expect(missingWarnings.single, contains('2 front history entries'));
    });
  });

  group('SP mention token rewriting (end-to-end)', () {
    String mentionMatcher(String prismMemberId) => '@[$prismMemberId]';

    test('member bios rewrite mentions with forward references', () {
      final data = _makeExportData(
        members: [
          const SpMember(
            id: 'sp-a',
            name: 'Alice',
            desc: 'Best friends with <###@sp-b###>!',
          ),
          const SpMember(id: 'sp-b', name: 'Bob'),
        ],
      );

      final result = SpMapper().mapAll(data);
      final alice = result.members.firstWhere((m) => m.name == 'Alice');
      final bob = result.members.firstWhere((m) => m.name == 'Bob');
      expect(alice.bio, 'Best friends with ${mentionMatcher(bob.id)}!');
    });

    test('note body rewrites mentions', () {
      final data = _makeExportData(
        members: [_memberA, _memberB],
        notes: [
          SpNote(
            id: 'n1',
            title: 'Memory',
            body: 'Today <###@sp-a###> and <###@sp-b###> went hiking.',
            memberId: 'sp-a',
            date: DateTime.utc(2024, 1, 1),
          ),
        ],
      );

      final result = SpMapper().mapAll(data);
      final a = result.members.firstWhere((m) => m.name == 'Alice');
      final b = result.members.firstWhere((m) => m.name == 'Bob');
      expect(
        result.notes.single.body,
        'Today ${mentionMatcher(a.id)} and ${mentionMatcher(b.id)} went hiking.',
      );
    });

    test('board message body rewrites mentions', () {
      final data = _makeExportData(
        members: [_memberA, _memberB],
        boardMessages: [
          SpBoardMessage(
            id: 'bm1',
            writtenBy: 'sp-a',
            writtenFor: 'sp-b',
            message: 'Hey <###@sp-b###>, miss you!',
            writtenAt: DateTime.utc(2024, 6, 1),
          ),
        ],
      );

      final result = SpMapper().mapAll(data);
      final b = result.members.firstWhere((m) => m.name == 'Bob');
      expect(result.boardPosts, hasLength(1));
      expect(
        result.boardPosts.single.body,
        'Hey ${mentionMatcher(b.id)}, miss you!',
      );
    });

    test('unresolved mention is preserved verbatim', () {
      final data = _makeExportData(
        members: [_memberA],
        notes: [
          SpNote(
            id: 'n1',
            title: 'X',
            body: 'Hi <###@sp-ghost###>',
            memberId: 'sp-a',
            date: DateTime.utc(2024, 1, 1),
          ),
        ],
      );

      final result = SpMapper().mapAll(data);
      expect(result.notes.single.body, 'Hi <###@sp-ghost###>');
    });

    test('chat message content rewrites mentions', () {
      final data = _makeExportData(
        members: [_memberA, _memberB],
        channels: [
          const SpChannel(id: 'ch1', name: 'general', memberIds: []),
        ],
        messages: [
          SpMessage(
            id: 'msg1',
            channelId: 'ch1',
            senderId: 'sp-a',
            content: 'Yo <###@sp-b###> ping',
            timestamp: DateTime.utc(2024, 6, 1),
          ),
        ],
      );

      final result = SpMapper().mapAll(data);
      final b = result.members.firstWhere((m) => m.name == 'Bob');
      expect(
        result.messages.single.content,
        'Yo ${mentionMatcher(b.id)} ping',
      );
    });

    test('group description rewrites mentions', () {
      final data = _makeExportData(
        members: [_memberA, _memberB],
        groups: [
          const SpGroup(
            id: 'g1',
            name: 'Adventurers',
            desc: 'Founded by <###@sp-a###>',
          ),
        ],
      );

      final result = SpMapper().mapAll(data);
      final a = result.members.firstWhere((m) => m.name == 'Alice');
      expect(
        result.groups.single.description,
        'Founded by ${mentionMatcher(a.id)}',
      );
    });

    test('custom field value rewrites mentions', () {
      final data = _makeExportData(
        members: [
          SpMember(
            id: 'sp-a',
            name: 'Alice',
            info: const <String, dynamic>{
              'cf-pair': 'paired with <###@sp-b###>',
            },
          ),
          _memberB,
        ],
        customFields: [
          const SpCustomFieldDef(id: 'cf-pair', name: 'Pair', type: 0),
        ],
      );

      final result = SpMapper().mapAll(data);
      final b = result.members.firstWhere((m) => m.name == 'Bob');
      expect(result.customFieldValues, hasLength(1));
      expect(
        result.customFieldValues.single.value,
        'paired with ${mentionMatcher(b.id)}',
      );
    });
  });

  group('Member createdAt from ObjectId timestamp', () {
    // A valid 24-char MongoDB ObjectId whose first 4 bytes decode to a known
    // timestamp. 0x507F1F77 = 1350419319 seconds since epoch → 2012-10-16.
    const validObjectId = '507f1f77bcf86cd799439011';
    final expectedCreatedAt = DateTime.fromMillisecondsSinceEpoch(
      0x507f1f77 * 1000,
      isUtc: true,
    );

    test('SP member with a valid ObjectId gets createdAt from the timestamp',
        () {
      final frozenNow = DateTime(2025, 1, 1);
      final data = _makeExportData(
        members: [const SpMember(id: validObjectId, name: 'Alice')],
      );

      final mapper = SpMapper(now: () => frozenNow);
      final result = mapper.mapAll(data);

      expect(result.members, hasLength(1));
      // createdAt must reflect the ObjectId timestamp, not the frozen clock.
      expect(result.members.first.createdAt, expectedCreatedAt);
      expect(result.members.first.createdAt, isNot(equals(frozenNow)));
    });

    test('SP member with empty/invalid id falls back to _now()', () {
      final frozenNow = DateTime(2025, 6, 15);
      final data = _makeExportData(
        members: [const SpMember(id: '', name: 'Ghost')],
      );

      final mapper = SpMapper(now: () => frozenNow);
      final result = mapper.mapAll(data);

      expect(result.members, hasLength(1));
      expect(result.members.first.createdAt, frozenNow);
    });

    test('SP member with a short (non-ObjectId) id falls back to _now()', () {
      final frozenNow = DateTime(2025, 6, 15);
      // 7 chars — too short for extractObjectIdTimestamp to parse.
      final data = _makeExportData(
        members: [const SpMember(id: 'abc1234', name: 'Short')],
      );

      final mapper = SpMapper(now: () => frozenNow);
      final result = mapper.mapAll(data);

      expect(result.members, hasLength(1));
      expect(result.members.first.createdAt, frozenNow);
    });

    test('custom front (CF) always gets createdAt from _now(), not ObjectId',
        () {
      final frozenNow = DateTime(2025, 3, 20);
      final data = _makeExportData(
        customFronts: [
          const SpCustomFront(id: validObjectId, name: 'Host'),
        ],
      );

      final mapper = SpMapper(now: () => frozenNow);
      final result = mapper.mapAll(data);

      expect(result.members, hasLength(1));
      // Custom fronts must use _now(), not the ObjectId timestamp.
      expect(result.members.first.createdAt, frozenNow);
      expect(result.members.first.createdAt, isNot(equals(expectedCreatedAt)));
    });
  });

  group('F18: deterministic SP member ids', () {
    test('two independent imports of the same SP member converge on one id', () {
      final data = _makeExportData(members: [_memberA]);
      final r1 = SpMapper().mapAll(data);
      final r2 = SpMapper().mapAll(data);
      expect(r1.members.single.id, r2.members.single.id,
          reason: 'fresh imports on two devices must mint the SAME local id so '
              'they converge on one CRDT row');
      expect(r1.members.single.id, deriveSpMemberId('sp-a'),
          reason: 'derived from the SP _id, not a random uuid');
    });

    test('an already-mapped SP member keeps its original id (sp_id_map reuse)',
        () {
      final data = _makeExportData(members: [_memberA]);
      // A prior import assigned a random id, persisted in sp_id_map and seeded
      // back as existingMappings — deterministic-id must NOT override it.
      final mapper = SpMapper(
        existingMappings: {
          'member': {'sp-a': 'legacy-random-id'},
        },
      );
      final result = mapper.mapAll(data);
      expect(result.members.single.id, 'legacy-random-id',
          reason: 'existing mapping wins; det-id only mints for unseen members');
    });
  });
}
